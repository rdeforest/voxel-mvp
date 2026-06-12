class_name DCTerrainManager
extends Node3D

# Our terrain render layer. Meshes a cube of terrain around the followed node (the player)
# with our C++ DCOctreeMesher and renders our mesh, re-meshing as the player moves. The SDF
# + material come from the EditStore (generator + edits) — the sole terrain data source.
#
# Threading: the per-level region reads (EditStore.fill_region / fill_indices_region) and the
# meshing pass (DCOctreeMesher) both run on a WorkerThreadPool task over an immutable store
# snapshot — never touching a Node or the live store from the thread. The finished arrays
# come back and the ArrayMesh is built on the main thread (RenderingServer upload).
#
# Meshes a distance-graded LOD clipmap: nested levels centred on the follow target,
# level k covering 2^k the extent at 2^k the cell size, each read at LOD k so coarse
# cells sample coarse data (no undersampling). One octree spans the whole clipmap;
# the refine matches cell size to the clipmap level so data LOD and cell size
# transition together. The mesher's point-location meshing stitches it crack-free
# with no balance pass needed.

# LOD levels. The base 5 gives 2048m world coverage at the 1m cell; sub-metre rendering shrinks
# each level's world extent by RENDER_SUBDIV, so we add one level per octave (RENDER_SUBDIV_LOG2)
# to keep the coarsest level — and the rendered horizon — at the same world distance. At 0.25 this
# is 7 levels: ±16m of 0.25m fine core, coarsening to 16m cells out to 2048m.
const LEVELS            := 5 + VoxelConstants.RENDER_SUBDIV_LOG2
const LEVEL_DIM         := 129    # samples per axis per level; LEVEL_DIM-1 must be a power of 2
                                  # 129 -> ±64m of 1m cells, so dramatic 3D terrain (overhangs,
                                  # relief) renders fine instead of undersampling into floating
                                  # islands. ~8x the mesh compute of 65 (perf is fine until <30fps).
const RECENTER_DISTANCE := 8.0    # re-mesh once the follow target drifts this far (m)

# Derived: octree root spans the coarsest level. ROOT = (LEVEL_DIM-1) << (LEVELS-1).
const _LEVEL_CELLS      := LEVEL_DIM - 1                 # 128
const _ROOT_DEPTH       := 7 + LEVELS - 1                # log2(128) + (LEVELS-1)
const _COARSEST_CELL    := 1 << (LEVELS - 1)             # snap granularity (16m)

var _edit_store: EditStore      # SDF + material source (generator + edits)
var _follow:  Node3D

var _mesh_instance: MeshInstance3D
var _enabled := false


# The grass surface material worn by our mesh when DC is the default render. A standalone
# resource (not the terrain node's) — Godot caches it by path, so the console `set`/`get` and
# the snapshot tunables load() the SAME instance and edit it live.
const TERRAIN_MATERIAL_PATH := "res://assets/materials/terrain_surface.tres"
var terrain_material: ShaderMaterial = load(TERRAIN_MATERIAL_PATH)

var _mesher := DCOctreeMesher.new()   # reused: holds the persistent collapse-hysteresis state
# A SEPARATE mesher for main-thread splices, so a splice can run while the worker is meshing a full
# build on `_mesher` without racing its state. mesh_subregion is self-contained (fresh octree, no
# hysteresis), so a second instance is safe.
var _splice_mesher := DCOctreeMesher.new()
var _task_id := -1
var _job_origin: Vector3i
var _job_arrays: Array = []
var _job_owners: PackedVector3Array = PackedVector3Array()
var _last_center := Vector3.INF
var _job_read_ms := 0
var _job_t0 := 0

# Cached displayed mesh (the last FULL build) so an edit can splice a re-meshed sub-box in
# place instead of rebuilding the whole clipmap (the ~5s full re-mesh). Owners are the
# per-triangle world owner-cell origin; _cache_origin is the root the verts are local to.
var _cache_arrays: Array = []
var _cache_owners: PackedVector3Array = PackedVector3Array()
var _cache_origin: Vector3i
const _EDIT_MARGIN_M := 3.0   # WORLD metres of slack around the edit box (covers the SDF influence);
                              # converted to base-cells per resolution so the world band stays constant
const _EDIT_APRON  := 4       # base-cells built beyond the core for stitching the seam (mesher stencil)
const _MAX_SPLICE_SPAN := 96  # base-cells; above this an edit does a full re-mesh instead of a splice

# Edit splices run ASYNC on a worker: at sub-metre a patch mesh is ~100ms — too slow for the main
# thread. World boxes wait in the queue; one splice job meshes on _splice_mesher at a time, applied
# (cheap array surgery) on the main thread when it lands (~1-2 frames). Edits seen during a full
# build are re-queued on _finish (the build's snapshot may predate them).
var _splice_queue: Array = []        # [[box_origin, box_size], ...] world boxes awaiting a splice
var _splice_task_id := -1
var _splice_core_min: Vector3i       # apply geometry captured at splice dispatch (base-cell units)
var _splice_core_max: Vector3i
var _splice_sub_origin: Vector3i
var _splice_patch: Array = []        # worker output: the meshed patch
var _splice_owners: PackedVector3Array = PackedVector3Array()  # ...and its per-triangle owner cells
var _edits_during_build: Array = []  # edits seen while a full build ran → re-queued on finish
const _MAX_QUEUE := 64               # cap; overflow → one full re-mesh covers the backlog

# Print per-recenter read/mesh timings to the output (tuning aid). Only fires while
# the manager is enabled, which is opt-in, so it's quiet in normal play.
var log_timings := true

# Error-driven LOD: coarsen by screen-space error (~eps_px) instead of distance bands.
# The mesher builds to the data floor then collapses bottom-up wherever one vertex fits
# the real fine surface within eps_px on screen (DCOctreeMesher::accumulate) — flat
# regions go coarse, curved stay fine, crack-free, and a coarse cell derives its vertex
# from accumulated FINE QEF so it sits on the fine surface (seams dissolve). Default ON
# since the collapse metric was fixed (undivided residual — thin features veto their own
# collapse, no more flapping; substrate Phase A). `dcerror`/`dceps` toggle and tune it.
var error_driven := true
var dump_next := false   # diagnostic: capture the next dispatch's input + output (dcdump cmd)
var _dump_armed := false
var _dump_dict := {}
# Screen-error collapse threshold. Since the collapse metric is the UNDIVIDED QEF
# residual (not per-plane RMS — see DCOctreeMesher::accumulate), this is a larger
# scale than a literal pixel count; ~8 coarsens curved terrain well while thin
# features veto their own collapse. Tune live with `dceps`.
var eps_px := 8.0


func setup(follow: Node3D, edit_store: EditStore) -> void:
    _edit_store = edit_store
    _follow  = follow
    _mesh_instance = MeshInstance3D.new()
    _mesh_instance.material_override = terrain_material
    # The mesh is built in BASE-CELL lattice units; this scale maps it back to world. The full
    # build and every splice produce lattice verts, so one instance scale covers both.
    _mesh_instance.scale = Vector3.ONE * VoxelConstants.RENDER_BASE_CELL
    add_child(_mesh_instance)
    # Re-mesh on terrain edits too (not just movement), so digs/builds show. Bound method ->
    # the bus weakrefs us and auto-prunes on scene reload. v1 re-meshes the whole clipmap;
    # incremental (just the edited region) is a later optimization.
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_terrain_edit)


func set_enabled(on: bool) -> void:
    _enabled = on
    if on:
        _last_center = Vector3.INF   # force an immediate re-mesh on next tick
    else:
        _mesh_instance.mesh = null


func is_enabled() -> bool:
    return _enabled

# Force a re-mesh on the next tick (after a live LOD-param change).
func remesh() -> void:
    _last_center = Vector3.INF


# Make DC the terrain render: start meshing now.
func start_default() -> void:
    set_enabled(true)


func _on_terrain_edit(event: TerrainSdfChangedEvent) -> void:
    # Queue an async splice so a dig/build shows in ~1-2 frames (the patch meshes on a worker —
    # at sub-metre a main-thread patch mesh would be a ~100ms hitch). Edits seen during a full
    # build are also recorded so they re-queue against the fresh mesh in _finish (the build's
    # snapshot may predate them).
    if not _enabled or _follow == null:
        return
    _enqueue_splice(event.box_origin, event.box_size)
    if _task_id != -1:
        _edits_during_build.append([event.box_origin, event.box_size])


func _enqueue_splice(box_origin: Vector3, box_size: Vector3) -> void:
    if _splice_queue.size() >= _MAX_QUEUE:
        _splice_queue.clear()
        _last_center = Vector3.INF   # backlog too deep → one full re-mesh covers it
        return
    _splice_queue.append([box_origin, box_size])


# Pop the next queued edit, work out its base-cell patch geometry, and dispatch the mesh to a
# worker (_splice_mesher). Falls back to a full re-mesh when the edit is outside the fine core or
# too big to splice. The store read happens on the worker (from a snapshot), so the main thread
# only does the cheap geometry + dispatch.
func _dispatch_splice() -> void:
    var base_cell := VoxelConstants.RENDER_BASE_CELL
    var entry: Array = _splice_queue.pop_front()
    var box_origin: Vector3 = entry[0]
    var box_size: Vector3 = entry[1]
    var margin := int(ceil(_EDIT_MARGIN_M / base_cell))   # world band → base-cells
    var lo := box_origin / base_cell                       # edit box in base-cell units
    var hi := (box_origin + box_size) / base_cell
    var root_half := float(1 << _ROOT_DEPTH) * 0.5
    var fine_half := float(_LEVEL_CELLS) * 0.5 - float(margin + _EDIT_APRON + 2)
    var off_center := ((lo + hi) * 0.5) - (Vector3(_cache_origin) + Vector3.ONE * root_half)
    if maxf(absf(off_center.x), maxf(absf(off_center.y), absf(off_center.z))) > fine_half:
        _last_center = Vector3.INF   # outside the fine core — the splice would meet coarse LOD
        return
    var core_min := Vector3i(lo.floor()) - Vector3i.ONE * margin
    var core_max := Vector3i(hi.ceil()) + Vector3i.ONE * margin
    var sub_origin := core_min - Vector3i.ONE * _EDIT_APRON
    var sub_hi := core_max + Vector3i.ONE * _EDIT_APRON
    var span := maxi(sub_hi.x - sub_origin.x, maxi(sub_hi.y - sub_origin.y, sub_hi.z - sub_origin.z))
    if span > _MAX_SPLICE_SPAN:
        _last_center = Vector3.INF   # too big to splice → full re-mesh
        return
    var sub_size := 1
    while sub_size < span:
        sub_size <<= 1
    _splice_core_min = core_min
    _splice_core_max = core_max
    _splice_sub_origin = sub_origin
    var snap: EditStore = _edit_store.duplicate()
    _splice_task_id = WorkerThreadPool.add_task(
        _splice_job.bind(snap, sub_origin, sub_size + 1, sub_size, MaterialPalette.colors()), false, "DC splice")


# Worker: read the edit region from the snapshot at the world cell, mesh the patch in lattice
# (cell 1; the mesh instance scale maps it to world). No Node/main-thread access — results land in
# _splice_patch/_splice_owners for _finish_splice to apply.
func _splice_job(store: EditStore, sub_origin: Vector3i, sub_dim: int, sub_size: int, palette: PackedColorArray) -> void:
    var world_cell := VoxelConstants.RENDER_BASE_CELL
    var sdf: PackedFloat32Array = store.fill_region(sub_origin, sub_dim, world_cell, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO)
    var idx: PackedByteArray = store.fill_indices_region(sub_origin, sub_dim, world_cell)
    _splice_patch = _splice_mesher.mesh_subregion(sdf, sub_dim, Vector3.ZERO, 1.0,
        sub_origin, sub_size, _splice_core_min, _splice_core_max, idx, palette)
    _splice_owners = _splice_mesher.get_last_triangle_owners()


# Apply the finished patch to the cached mesh (cheap array surgery, main thread).
func _finish_splice() -> void:
    WorkerThreadPool.wait_for_task_completion(_splice_task_id)
    _splice_task_id = -1
    if _splice_patch.is_empty() or _cache_arrays.is_empty():
        return
    _apply_splice(_splice_core_min, _splice_core_max, _splice_sub_origin, _splice_patch, _splice_owners)


# Swap the cached mesh's triangles in the core box for the patch's (DCEditSplicer does the
# pure array surgery), then upload. Runs on the main thread — O(triangles) (~ms), not the
# 10M-cell full rebuild. The spliced result becomes the base for the next edit.
func _apply_splice(core_min: Vector3i, core_max: Vector3i, sub_origin: Vector3i,
        patch: Array, patch_owners: PackedVector3Array) -> void:
    var r := DCEditSplicer.splice(_cache_arrays, _cache_owners, _cache_origin,
        core_min, core_max, sub_origin, patch, patch_owners)
    var arrays: Array = r.arrays
    var mesh := ArrayMesh.new()
    if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    _mesh_instance.mesh = mesh
    _cache_arrays = arrays
    _cache_owners = r.owners
    Perf.mark_event()


func _process(_dt: float) -> void:
    if not _enabled or _follow == null:
        return
    var t0 := Time.get_ticks_usec()
    if _task_id != -1:
        if WorkerThreadPool.is_task_completed(_task_id):
            _finish()
            Perf.mark_event()   # mark the frame the new mesh is applied (correlate spikes)
    else:
        var center := _follow.global_position
        if center.distance_to(_last_center) > RECENTER_DISTANCE:
            _dispatch(center)
    # Async edit splices run on their own worker, concurrent with a full build.
    if _splice_task_id != -1:
        if WorkerThreadPool.is_task_completed(_splice_task_id):
            _finish_splice()
    elif not _splice_queue.is_empty() and not _cache_arrays.is_empty():
        _dispatch_splice()
    Perf.report("DC mesh (main)", (Time.get_ticks_usec() - t0) / 1000.0)


# Integer halving of a non-negative size. The one spot that acknowledges the
# integer-division warning, so the call sites above read as plain arithmetic.
static func _half(n: int) -> int:
    @warning_ignore("integer_division")
    return n / 2

func _dispatch(center: Vector3) -> void:
    # All octree geometry below is in BASE-CELL units (one unit = RENDER_BASE_CELL metres). The
    # mesher meshes a pure integer lattice in these units; the store is read at the matching world
    # cell (base_cell * 2^k); the output mesh is scaled back to world by base_cell at _finish. At
    # base_cell = 1.0 this is identical to the old metre-based math.
    var base_cell := VoxelConstants.RENDER_BASE_CELL
    var center_bc := center / base_cell                    # follow target in base-cell units
    var root_size := 1 << _ROOT_DEPTH                       # extent of the coarsest level (base-cells)
    # Snap the centre to the coarsest cell so every level's read origin lands on its
    # own LOD grid (floor-snap, so it's stable across the world origin).
    var coarse_cell_origin := Vector3i((center_bc / float(_COARSEST_CELL)).floor()) * _COARSEST_CELL
    var root_origin := coarse_cell_origin - Vector3i.ONE * _half(root_size)
    var center_lattice := Vector3.ONE * _half(root_size)    # follow target, lattice space
    # Per-level clipmap geometry (cheap, main thread); the store reads themselves run on the
    # worker (10M generator evals would stall the frame here). Per level k: lattice origin,
    # cell size (LOD k = 2^k), and the world origin in CELL units (the fill_region argument —
    # world_origin is a multiple of cell, so the integer divide is exact).
    var level_origins := PackedVector3Array()
    var level_cells := PackedFloat32Array()
    var level_world_cells := PackedVector3Array()
    for k in LEVELS:
        var cell := 1 << k
        var half_k := _half(_LEVEL_CELLS) << k              # lattice half-extent of level k
        var lattice_origin := Vector3i.ONE * (_half(root_size) - half_k)
        var world_origin := root_origin + lattice_origin
        @warning_ignore("integer_division")
        var world_cells := world_origin / cell             # exact: world_origin is a multiple of cell
        level_origins.append(Vector3(lattice_origin))
        level_cells.append(float(cell))
        level_world_cells.append(Vector3(world_cells))
    _job_read_ms = 0                                        # reads moved to the worker
    _job_t0      = Time.get_ticks_msec()
    _job_origin  = root_origin
    _job_arrays  = []
    _last_center = center
    var half0 := float(_LEVEL_CELLS) * 0.5
    # Capture the camera (main thread) for error-driven LOD: viewpoint in lattice
    # space + the perspective projection factor (px per world unit at unit distance).
    var camera_lattice := center_lattice
    var proj := 0.0
    var cam := get_viewport().get_camera_3d()
    if cam != null:
        camera_lattice = cam.global_position / base_cell - Vector3(root_origin)   # world -> base-cell lattice
        var vp_h := float(get_viewport().get_visible_rect().size.y)
        proj = vp_h / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
    if dump_next:
        _arm_dump(center_lattice, camera_lattice, half0, proj, root_origin)
    # An immutable snapshot of the sparse store for the worker (cheap — copies only edited
    # nodes; unedited world stays the on-demand generator).
    var job_store: EditStore = _edit_store.duplicate()
    _task_id = WorkerThreadPool.add_task(
        _mesh_job.bind(job_store, level_world_cells, level_origins, level_cells, center_lattice, half0,
            camera_lattice, proj, eps_px, error_driven, root_origin,
            MaterialPalette.colors()), false, "DC terrain mesh")


# Runs on a worker thread: read each clipmap level from the (immutable) store snapshot, then
# build + mesh one octree over them with the C++ DCOctreeMesher. Pure computation over the
# snapshot + immutable PackedArrays — safe off the main thread (no Node / engine access).
func _mesh_job(store: EditStore, level_world_cells: PackedVector3Array,
        level_origins: PackedVector3Array, level_cells: PackedFloat32Array,
        center: Vector3, half0: float, camera: Vector3, proj: float, eps: float, err: bool,
        world_origin: Vector3i, palette: PackedColorArray) -> void:
    var base_cell := VoxelConstants.RENDER_BASE_CELL
    var level_data: Array = []
    var level_indices: Array = []
    for k in LEVELS:
        var cell: float = level_cells[k]            # LATTICE stride (1<<k) — what the mesher meshes
        var world_cell := base_cell * cell          # WORLD spacing the store is sampled at
        var wc := Vector3i(level_world_cells[k])     # level origin in world_cell units
        level_data.append(store.fill_region(wc, LEVEL_DIM, world_cell, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO))
        level_indices.append(store.fill_indices_region(wc, LEVEL_DIM, world_cell))
    if _dump_armed:
        _dump_dict["level_data"] = level_data
        _dump_dict["origins"]    = level_origins
        _dump_dict["cells"]      = level_cells
    _job_arrays = _mesher.mesh_clipmap(
        level_data, LEVEL_DIM, level_origins, level_cells, center, half0, _ROOT_DEPTH,
        camera, proj, eps, err, world_origin, level_indices, palette,
        true,   # uniform 1m fine core (splice-able)
        0.0)    # surface-sparse prune DISABLED: the local-gradient bound is unreliable on
                # godot_voxel's lossy-encoded + geomorph-blended multi-level SDF (it over-prunes
                # real surface -> big slivers). Safe at lod 0 only; needs a mip-robust bound.
    _job_owners = _mesher.get_last_triangle_owners()


# Diagnostic (dcdump): write this dispatch's mesher INPUT (clipmap SDF + params) paired
# with the OUTPUT mesh it produced, so the exact case can be replayed and audited
# headlessly — and the displayed mesh inspected directly (Mesh.ARRAY_* arrays).
func _arm_dump(center: Vector3, camera: Vector3, half0: float, proj: float, root_origin: Vector3i) -> void:
    dump_next = false
    _dump_armed = true
    # level_data / origins / cells are filled in by _mesh_job once the worker reads the store.
    _dump_dict = {
        "dim": LEVEL_DIM,
        "center": center, "camera": camera, "half0": half0, "depth": _ROOT_DEPTH,
        "proj": proj, "eps": eps_px, "err": error_driven, "root_origin": root_origin,
    }


func _dump_write() -> void:
    _dump_armed = false
    _dump_dict["mesh"] = _job_arrays
    _dump_dict["mesh_origin"] = _job_origin
    var f := FileAccess.open("user://dcdump.dat", FileAccess.WRITE)
    f.store_var(_dump_dict, true)
    f.close()
    _dump_dict = {}
    print("dcdump written: ", ProjectSettings.globalize_path("user://dcdump.dat"))


func _finish() -> void:
    WorkerThreadPool.wait_for_task_completion(_task_id)
    _task_id = -1
    if _dump_armed:
        _dump_write()
    if _job_arrays.is_empty():
        _mesh_instance.mesh = null
        _edits_during_build.clear()
        return
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _job_arrays)
    _mesh_instance.mesh = mesh
    _mesh_instance.global_position = Vector3(_job_origin) * VoxelConstants.RENDER_BASE_CELL   # base-cell origin -> world
    _cache_arrays = _job_arrays           # this full build is now the splice base
    _cache_owners = _job_owners
    _cache_origin = _job_origin
    if log_timings:
        var verts: int = (_job_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
        print("DC clipmap: %d verts — read %d ms (main), mesh %d ms (worker)" % [
            verts, _job_read_ms, Time.get_ticks_msec() - _job_t0])
    # The worker's snapshot was taken at dispatch, so edits during the build may be absent from the
    # fresh mesh. Re-queue them for an async splice onto it (a brief 1-2 frame gap, no main-thread hitch).
    for entry in _edits_during_build:
        _enqueue_splice(entry[0], entry[1])
    _edits_during_build.clear()


# Scan the currently displayed mesh for bad triangles (dcaudit cmd). Pure observer —
# reads the on-screen mesh and does NOT re-mesh (a rebuild can mask a stale-mesh
# artifact). The triangle classification lives in DCMeshAudit.
func audit_current_mesh() -> void:
    if _mesh_instance == null or _mesh_instance.mesh == null or _mesh_instance.mesh.get_surface_count() == 0:
        print("dcaudit: no DC mesh on screen")
        return
    DCMeshAudit.report(_mesh_instance.mesh.surface_get_arrays(0), Vector3i(_mesh_instance.global_position))


func _exit_tree() -> void:
    # Don't let the pool run our callable into a freed object.
    if _task_id != -1:
        WorkerThreadPool.wait_for_task_completion(_task_id)
        _task_id = -1
