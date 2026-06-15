class_name DCTerrainManager
extends Node3D

# Emitted whenever an edit or movement invalidates a region. kind 0 = voxels changed (blue),
# 1 = triangles re-meshed (green). World-space AABB. The invalidation overlay listens; no-op
# otherwise. Fires for splices AND fallbacks (so the over-reach is visible even when it bails).
signal region_invalidated(box_min: Vector3, box_max: Vector3, kind: int)
# The ACTUAL cache triangles inside an edit's invalidation region (world-space verts, groups of 3),
# so the overlay can draw the real LOD/cell structure the alignment grabbed. Collected only when
# debug_invalidation is on (the scan is O(cache triangles)).
signal triangles_invalidated(world_verts: PackedVector3Array)
var debug_invalidation := false   # set by `dcinval`; gates the (costly) triangle scan above

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
var frozen := false        # examine mode: stop dispatching re-meshes so the current mesh holds still


# The grass surface material worn by our mesh when DC is the default render. A standalone
# resource (not the terrain node's) — Godot caches it by path, so the console `set`/`get` and
# the snapshot tunables load() the SAME instance and edit it live.
const TERRAIN_MATERIAL_PATH := "res://assets/materials/terrain_surface.tres"
var terrain_material: ShaderMaterial = load(TERRAIN_MATERIAL_PATH)
# Examine-mode override: double-sided, magenta backfaces (tell a backwards triangle from a hole).
const BACKFACE_MATERIAL_PATH := "res://assets/materials/dc_backface_debug.tres"

var _mesher := DCOctreeMesher.new()   # reused: holds the persistent collapse-hysteresis state

# B1: splices now run on _mesher (same instance as the full build) so the collapse-hysteresis set
# is shared — requirement (c) for crack-free LOD-boundary splices. Splices are serialized
# (only dispatched when _task_id == -1) so there is no data race.
var _task_id := -1
var _last_center := Vector3.INF
var _last_proj := 0.0   # proj of the last build; a live FOV/zoom change re-meshes (telescope refines)

# A meshed DC surface tagged for splicing: the Mesh.ARRAY_* surface, the per-triangle owner-cell
# origin + size, and the world-lattice root its vertices are local to. `_cache` is what's on screen
# (the last full build, kept as the splice base); `_job` is an in-flight full build's output.
class DcMesh:
    var arrays: Array = []
    var owners: PackedVector3Array = PackedVector3Array()
    var sizes:  PackedFloat32Array = PackedFloat32Array()
    var origin: Vector3i
    func empty() -> bool:
        return arrays.is_empty()
    func bundle() -> Dictionary:   # the {arrays, owners, sizes} the splicer takes
        return {"arrays": arrays, "owners": owners, "sizes": sizes}

var _job   := DcMesh.new()
var _cache := DcMesh.new()
var _build_read_ms := 0   # the in-flight build's store-read time (ms)
var _build_t0 := 0        # ...and when it started (ms)

# Re-mesh slack beyond the edit box, in CELLS — the Dual-Contouring stencil, NOT a metric distance.
# A changed SDF corner only moves the surface (and its triangles) within ~2 cells of itself, plus
# ~1 cell for the SDF_AIR clear pulling the surface into a solid neighbour — independent of how big
# the edit is. The edit BOX already scales with the edit; this is the small fixed halo around it.
# (Was 3 m = 12 cells at 0.25 m, which re-meshed a ~6 m band around a single 0.25 m voxel.)
const _EDIT_STENCIL_CELLS := 3
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
var _splice_patch:        Array              = []              # worker output: the meshed patch
var _splice_owners:      PackedVector3Array = PackedVector3Array()  # per-triangle owner cells
var _splice_owner_sizes: PackedFloat32Array = PackedFloat32Array()  # per-triangle owner sizes
var _edits_during_build: Array = []  # edits seen while a full build ran → re-queued on finish

# The clipmap geometry of the last full build — what a splice re-uses so it meshes the same levels
# at the same tolerance on the same frame and lands on the same cells.
class ClipmapView:
    var level_world_cells: PackedVector3Array = PackedVector3Array()
    var level_origins:     PackedVector3Array = PackedVector3Array()
    var level_cells:       PackedFloat32Array = PackedFloat32Array()
    var center_lattice:    Vector3
    var half0:             float
    var camera_lattice:    Vector3
    var proj:              float
    var eps_px:            float
    var error_driven:      bool
    var uniform_core:      bool
    func ready() -> bool:
        return not level_cells.is_empty()

var _clipmap := ClipmapView.new()

# Edit-latency trace (per splice; emitted in _finish_splice when the perf card is shown). Decomposes
# click→visible into wait / sched / work / detect / apply so we can see WHAT the edit waits on:
# queue/in-flight build (wait), worker pickup (sched), the C++ mesh (work), main-thread poll (detect),
# splicer array surgery (apply). Timestamps are µs (Time.get_ticks_usec), cross-thread-safe to read.
var _trace_edit_us       := 0
var _trace_dispatch_us   := 0
var _trace_work_start_us := 0
var _trace_work_end_us   := 0
const _MAX_QUEUE := 64               # cap; overflow → one full re-mesh covers the backlog

# Print per-recenter read/mesh timings to the output (tuning aid). Only fires while
# the manager is enabled, which is opt-in, so it's quiet in normal play.
var log_timings := true

# Screen-space-error LOD: the mesher builds to the data floor then collapses bottom-up
# wherever one vertex's projected error (we * proj / dist) is within eps_px on screen
# (DCOctreeMesher::accumulate) — flat/distant regions go coarse, near/curved stay fine,
# crack-free, and a coarse cell derives its vertex from accumulated FINE QEF so it sits on
# the fine surface (seams dissolve). The camera IS an input now (Stage 1): moving recoarsens
# receding terrain and a narrow FOV (telescope) refines distant terrain. Default ON.
# `dcerror`/`dceps` toggle and tune it.
var error_driven := true
var dump_next := false   # diagnostic: capture the next dispatch's input + output (dcdump cmd)
var _dump_armed := false
var _dump_dict := {}
# Screen-error threshold (px): the max projected QEF residual at which one vertex may stand
# in for a cell's fine surface. Smaller = more detail kept. ~2px is the doc target; B2 tunes
# it to the frame budget.
var eps_px := 2.0

# Pin the finest clipmap level (level 0) — the 1m core bubble around the camera — so it never
# collapses by screen error. ON keeps edits near the player landing in uniform 1m cells with clean
# boundaries the splice can patch crack-free; OFF lets the core coarsen too (uniform huge triangles
# at high eps, but edits there may crack / force a full rebuild). `dccore` toggles it. Default ON.
var uniform_core := true

# B2 budget controller. Detail self-tunes toward a frame-time target — refine when there's slack,
# coarsen when over budget — by nudging eps_px (the screen-error collapse threshold; smaller
# = more detail). Slow and damped: each change re-meshes the clipmap, so it acts once per
# BUDGET_INTERVAL and only when the frame time is clearly outside the target band. Default-on
# (`dcbudget` toggles it); it only helps a TRIANGLE-bound frame, on a shader/CPU-bound one it sheds
# detail for no gain — toggle off to hand-tune `dceps` (the budget loop overrides eps when on). This
# is the single global detail knob.
const BUDGET_TARGET_MS := 16.0   # the frame budget detail is allowed to spend up to (~60 fps)
const BUDGET_INTERVAL  := 1.0    # seconds between adjustments (re-mesh isn't free)
const EPS_MIN := 0.5
const EPS_MAX := 16.0
var budget_enabled := true
var _budget_clock := 0.0


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

# Examine mode: swap the terrain mesh to the double-sided backface-debug material (magenta
# backfaces) or back to the normal grass material. No re-mesh — just the material override.
func set_debug_backface(on: bool) -> void:
    _mesh_instance.material_override = (load(BACKFACE_MATERIAL_PATH) if on else terrain_material)

# Force a re-mesh on the next tick (after a live LOD-param change).
func remesh() -> void:
    _last_center = Vector3.INF


# B2: once per interval, push the tolerance toward the frame budget and re-mesh if it moved. Skips
# while a build/splice is in flight (don't retune mid-work) so it never fights the cost it's measuring.
func _tune_quality(dt: float) -> void:
    if not budget_enabled or _task_id != -1 or _splice_task_id != -1:
        return
    _budget_clock += dt
    if _budget_clock < BUDGET_INTERVAL:
        return
    _budget_clock = 0.0
    var frame_ms := 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)
    var tuned := _eps_for(frame_ms)
    if Perf.is_shown():
        Perf.status("budget", "%.1f ms/frame → eps %.2fpx" % [frame_ms, tuned])   # show state each tick
    if is_equal_approx(tuned, eps_px):
        return
    eps_px = tuned
    remesh()

# More detail when there's slack, less when over budget, unchanged within the target band.
func _eps_for(frame_ms: float) -> float:
    if frame_ms > BUDGET_TARGET_MS * 1.1:
        return minf(EPS_MAX, eps_px * 1.15)
    if frame_ms < BUDGET_TARGET_MS * 0.8:
        return maxf(EPS_MIN, eps_px * 0.92)
    return eps_px


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
    _splice_queue.append([box_origin, box_size, Time.get_ticks_usec()])


# Lazy re-mesh: replace just the triangles an edit changed, not the whole clipmap. The splice builds
# on the FULL build's frame (root_origin / _ROOT_DEPTH) with a BUILD-BOX restricting the descent to the
# edit box + apron and an EMIT-BOX restricting output to the core — so its cells land on the full
# build's exact lattice and neighbours and the patch reproduces it crack-free (no offset sub-octree,
# no alignment, no LOD rejection — see test_dc_lod_splice). Serialized behind any in-flight full build
# so the cache it patches isn't swapped mid-splice.
func _dispatch_splice() -> void:
    if _full_build_running():
        return                          # edits wait in _edits_during_build; they splice after it
    if not _have_cached_mesh():
        _request_full_rebuild()
        return
    var edit := _next_edit()
    var core := _edit_core_cells(edit)
    var span := _extent(core.min, core.max)
    if span > _MAX_SPLICE_SPAN:
        _give_up_to_full_rebuild(edit, span)   # a huge edit isn't worth a giant build-box
        return
    _show_invalidation(edit, core)
    _start_splice(edit, core)


func _full_build_running() -> bool:
    return _task_id != -1

func _have_cached_mesh() -> bool:
    return _clipmap.ready()

func _next_edit() -> Dictionary:
    var e: Array = _splice_queue.pop_front()
    return {"origin": e[0], "size": e[1], "queued_us": e[2] if e.size() > 2 else Time.get_ticks_usec()}

# The edit's world box in base-cells, padded by the DC stencil (a changed corner only moves the
# surface a few cells out). The box scales with the edit; this halo is the small fixed part.
func _edit_core_cells(edit: Dictionary) -> Dictionary:
    var base_cell := VoxelConstants.RENDER_BASE_CELL
    var lo: Vector3 = edit.origin / base_cell
    var hi: Vector3 = (edit.origin + edit.size) / base_cell
    var halo := Vector3i.ONE * _EDIT_STENCIL_CELLS
    return {"min": Vector3i(lo.floor()) - halo, "max": Vector3i(hi.ceil()) + halo}

# Stitch apron (base-cells) around the core: any displayed cell ADJACENT to the core must build to
# its data floor and collapse identically to the full build, so the apron must contain it whole. The
# coarsest cell near the edit bounds that, so the apron tracks the local LOD — small near the player
# (fine cells), larger out in the coarse bands — keeping the build-box proportional to the edit.
func _splice_apron(core: Dictionary) -> int:
    var probe := Vector3i.ONE * _EDIT_APRON
    var local_cell := _coarsest_owner_in(core.min - probe, core.max + probe)
    return 2 * local_cell + _EDIT_APRON

func _show_invalidation(edit: Dictionary, core: Dictionary) -> void:
    region_invalidated.emit(edit.origin, edit.origin + edit.size, 0)
    if debug_invalidation:
        triangles_invalidated.emit(_cache_tris_in(core.min, core.max))

func _start_splice(edit: Dictionary, core: Dictionary) -> void:
    _splice_core_min   = core.min
    _splice_core_max   = core.max
    _trace_edit_us     = edit.queued_us
    _trace_dispatch_us = Time.get_ticks_usec()
    var apron := Vector3i.ONE * _splice_apron(core)
    _splice_task_id = WorkerThreadPool.add_task(
        _splice_job.bind(_edit_store.duplicate(), core.min, core.max,
            core.min - apron, core.max + apron, MaterialPalette.colors()),
        false, "DC splice")

func _request_full_rebuild() -> void:
    _last_center = Vector3.INF

func _give_up_to_full_rebuild(edit: Dictionary, span: int) -> void:
    _request_full_rebuild()
    _trace_fallback(edit.queued_us, "edit too big to splice (%d cells)" % span)

func _extent(lo: Vector3i, hi: Vector3i) -> int:
    var d := hi - lo
    return maxi(d.x, maxi(d.y, d.z))


# Worker: read each clipmap level from the snapshot, then mesh on the FULL build's frame
# (root_origin / _ROOT_DEPTH, the same level geometry + camera + tol as the cache) with a BUILD-BOX
# restricting the descent to [build_min, build_max) and an EMIT-BOX to [core_min, core_max). The
# built cells therefore share the full build's exact lattice + neighbours, so the patch reproduces it
# over the core and stitches crack-free; the build-box leaf-terminates everything else, so cost stays
# proportional to the edit. Patch verts land in the cache's frame (no shift). No Node/main access.
func _splice_job(store: EditStore, core_min: Vector3i, core_max: Vector3i,
        build_min: Vector3i, build_max: Vector3i, palette: PackedColorArray) -> void:
    _trace_work_start_us = Time.get_ticks_usec()
    var base_cell := VoxelConstants.RENDER_BASE_CELL
    var level_data: Array = []
    var level_idxs: Array = []
    for k in LEVELS:
        var world_cell := base_cell * _clipmap.level_cells[k]
        var wc := Vector3i(_clipmap.level_world_cells[k])
        level_data.append(store.fill_region(wc, LEVEL_DIM, world_cell, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO))
        level_idxs.append(store.fill_indices_region(wc, LEVEL_DIM, world_cell))
    _splice_patch = _mesher.mesh_clipmap(
        level_data, LEVEL_DIM, _clipmap.level_origins, _clipmap.level_cells,
        _clipmap.center_lattice, _clipmap.half0, _ROOT_DEPTH,
        _clipmap.camera_lattice, _clipmap.proj, _clipmap.eps_px, _clipmap.error_driven,
        _cache.origin, level_idxs, palette,
        _clipmap.uniform_core, 0.0,      # uniform_core: match the full build this patches; prune_safety=0
        core_min, core_max,              # emit box: only output triangles in the edit core
        build_min, build_max)            # build box: descend only the edit box + apron
    _splice_owners      = _mesher.get_last_triangle_owners()
    _splice_owner_sizes = _mesher.get_last_triangle_owner_sizes()
    _trace_work_end_us = Time.get_ticks_usec()


# Apply the finished patch to the cached mesh (cheap array surgery, main thread).
func _finish_splice() -> void:
    WorkerThreadPool.wait_for_task_completion(_splice_task_id)
    var finish_us := Time.get_ticks_usec()
    _splice_task_id = -1
    if _splice_patch.is_empty() or _cache.arrays.is_empty():
        return
    _apply_splice(_splice_core_min, _splice_core_max,
        _splice_patch, _splice_owners, _splice_owner_sizes)
    if Perf.is_shown():
        _trace_emit(finish_us, Time.get_ticks_usec())


# Print the click→visible breakdown for one spliced edit. WORK is the C++ mesh (the GPU/algorithm
# lever); a big wait means it sat behind another job; detect/sched are frame-poll quantisation.
func _trace_emit(finish_us: int, visible_us: int) -> void:
    var wait   := (_trace_dispatch_us   - _trace_edit_us)       / 1000.0
    var sched  := (_trace_work_start_us - _trace_dispatch_us)   / 1000.0
    var work   := (_trace_work_end_us   - _trace_work_start_us) / 1000.0
    var detect := (finish_us            - _trace_work_end_us)   / 1000.0
    var apply  := (visible_us           - finish_us)            / 1000.0
    var total  := (visible_us           - _trace_edit_us)       / 1000.0
    print("edit→view %6.1fms | wait %5.1f  sched %4.1f  WORK %6.1f  detect %4.1f  apply %5.1f" % [
        total, wait, sched, work, detect, apply])
    Toast.show_message("edit→view %.0fms (work %.0f, wait %.0f, apply %.0f)" % [total, work, wait, apply], Color(0.78, 0.88, 1.0))


# An edit that couldn't splice took the full-rebuild path — note it so the slow case is visible.
func _trace_fallback(edit_us: int, reason: String) -> void:
    if not Perf.is_shown():
        return
    print("edit→view: FULL re-mesh fallback (%s) — %.1fms since click" % [reason, (Time.get_ticks_usec() - edit_us) / 1000.0])
    Toast.show_message("edit → full re-mesh: %s" % reason, Color(1.0, 0.85, 0.5))


# Swap the cached mesh's core-box triangles for the patch's (DCEditSplicer does the array surgery),
# then display the result — it becomes the base for the next edit. Main thread, O(triangles) (~ms).
# The patch was meshed on the cache's own frame (full-frame build-box), so its verts need no shift.
func _apply_splice(core_min: Vector3i, core_max: Vector3i,
        patch: Array, patch_owners: PackedVector3Array,
        patch_owner_sizes: PackedFloat32Array) -> void:
    var patch_mesh := {"arrays": patch, "owners": patch_owners, "sizes": patch_owner_sizes}
    var spliced := DCEditSplicer.splice(_cache.bundle(), patch_mesh, core_min, core_max, Vector3.ZERO)
    _show_mesh(spliced.arrays)
    _cache.arrays = spliced.arrays
    _cache.owners = spliced.owners
    _cache.sizes  = spliced.sizes
    Perf.mark_event()

# Build an ArrayMesh from surface arrays and put it on screen.
func _show_mesh(arrays: Array) -> void:
    var mesh := ArrayMesh.new()
    if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    _mesh_instance.mesh = mesh


func _process(dt: float) -> void:
    if not _enabled or _follow == null:
        return
    _tune_quality(dt)
    var t0 := Time.get_ticks_usec()
    if _task_id != -1:
        if WorkerThreadPool.is_task_completed(_task_id):
            _finish()
            Perf.mark_event()   # mark the frame the new mesh is applied (correlate spikes)
    else:
        var center := _follow.global_position
        var drift := center.distance_to(_last_center)
        var fov_changed := not is_equal_approx(_view_proj(), _last_proj)
        if (drift > RECENTER_DISTANCE or fov_changed) and not frozen:
            if Perf.is_shown() and is_finite(drift):
                var why := ("walked %.1fm" % drift) if drift > RECENTER_DISTANCE else "FOV change"
                print("recenter: %s → full rebuild (movement/FOV re-mesh, B3)" % why)
            _dispatch(center)
    # Async edit splices run on their own worker, concurrent with a full build.
    if _splice_task_id != -1:
        if WorkerThreadPool.is_task_completed(_splice_task_id):
            _finish_splice()
    elif not frozen and not _splice_queue.is_empty() and not _cache.arrays.is_empty() and _task_id == -1:
        _dispatch_splice()
    Perf.report("DC mesh (main)", (Time.get_ticks_usec() - t0) / 1000.0)
    if Perf.is_shown():
        var blocked := ""
        if not _splice_queue.is_empty():
            blocked = " — waiting: full build" if _task_id != -1 else (" — waiting: splice" if _splice_task_id != -1 else "")
        var verts := 0
        if not _cache.arrays.is_empty():
            verts = (_cache.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
        # Displayed vert count: if this CLIMBS as you edit (vs a fresh full build), the splice is
        # leaving geometry behind — the heavier mesh is what the shader then pays for every frame.
        Perf.status("DC", "verts %d  build %s  splice %s  queue %d%s" % [
            verts,
            "RUN" if _task_id != -1 else "idle",
            "RUN" if _splice_task_id != -1 else "idle",
            _splice_queue.size(), blocked])


# Integer halving of a non-negative size. The one spot that acknowledges the
# integer-division warning, so the call sites above read as plain arithmetic.
static func _half(n: int) -> int:
    @warning_ignore("integer_division")
    return n / 2

# The coarsest displayed cell whose extent overlaps a base-cell box (1 where the cache is finest).
# Used to size a splice's stitch apron to the local LOD.
func _coarsest_owner_in(box_min: Vector3i, box_max: Vector3i) -> int:
    var coarsest := 1
    for tri in _cache.owners.size():
        var o: Vector3 = _cache.owners[tri]
        var sz := int(_cache.sizes[tri]) if tri < _cache.sizes.size() else 1
        if o.x + sz > box_min.x and o.x < box_max.x \
                and o.y + sz > box_min.y and o.y < box_max.y \
                and o.z + sz > box_min.z and o.z < box_max.z:
            coarsest = maxi(coarsest, sz)
    return coarsest

# World-space verts (groups of 3) of cache triangles whose owner cell falls in a base-cell box —
# the real geometry the invalidation overlay draws. world = (cache_origin + lattice_vert)*base_cell.
func _cache_tris_in(region_min: Vector3i, region_max: Vector3i) -> PackedVector3Array:
    var out := PackedVector3Array()
    if _cache.arrays.is_empty():
        return out
    var verts: PackedVector3Array = _cache.arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = _cache.arrays[Mesh.ARRAY_INDEX]
    var base_cell := VoxelConstants.RENDER_BASE_CELL
    var origin := Vector3(_cache.origin)
    for t in _cache.owners.size():
        var o: Vector3 = _cache.owners[t]
        if o.x >= region_min.x and o.x < region_max.x \
                and o.y >= region_min.y and o.y < region_max.y \
                and o.z >= region_min.z and o.z < region_max.z:
            for j in 3:
                out.append((origin + verts[idx[t * 3 + j]]) * base_cell)
    return out

# The perspective projection factor (px per world unit at unit distance) of the live camera, or
# 0 with no camera. Position-independent — only FOV + viewport height — so it's the FOV-change probe.
func _view_proj() -> float:
    var cam := get_viewport().get_camera_3d()
    if cam == null:
        return 0.0
    var vp_h := float(get_viewport().get_visible_rect().size.y)
    return vp_h / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))


func _dispatch(center: Vector3) -> void:
    # All octree geometry below is in BASE-CELL units (one unit = RENDER_BASE_CELL metres). The
    # mesher meshes a pure integer lattice in these units; the store is read at the matching world
    # cell (base_cell * 2^k); the output mesh is scaled back to world by base_cell at _finish. At
    # base_cell = 1.0 this is identical to the old metre-based math.
    var base_cell := VoxelConstants.RENDER_BASE_CELL
    var center_bc := center / base_cell                    # follow target in base-cell units
    var root_size := 1 << _ROOT_DEPTH                       # extent of the coarsest level (base-cells)
    # Snap the centre to the coarsest cell so every level's read origin lands on its own LOD grid.
    # Snap to the NEAREST cell, not the lower one: the fine core is then centred on you to within
    # half a snap cell (±8m) instead of trailing up to a full cell (16m) behind, so forward detail
    # and forward edits aren't starved of fine LOD.
    var coarse_cell_origin := Vector3i((center_bc / float(_COARSEST_CELL)).round()) * _COARSEST_CELL
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
    _build_read_ms = 0                                        # reads moved to the worker
    _build_t0      = Time.get_ticks_msec()
    _job.origin  = root_origin
    _job.arrays  = []
    _last_center = center
    var half0 := float(_LEVEL_CELLS) * 0.5
    # Invalidation overlay: a full rebuild re-meshes the whole clipmap; show the fine (level-0)
    # region as the representative "this got redone" box (green) — so movement lights it up.
    var fine_w := half0 * base_cell
    region_invalidated.emit(center - Vector3.ONE * fine_w, center + Vector3.ONE * fine_w, 1)
    # Screen-error LOD inputs (main thread): the viewpoint in root-local lattice space and the
    # perspective projection factor (px per world unit at unit distance). camera shares the cell
    # frame the mesher collapses in (root-local base-cells), so we·proj/dist projects correctly.
    var camera_lattice := center_lattice
    var cam := get_viewport().get_camera_3d()
    if cam:
        camera_lattice = cam.global_position / base_cell - Vector3(root_origin)
    var proj := _view_proj()
    _last_proj = proj   # FOV-change trigger compares the live proj against this
    # Capture so splices can run mesh_clipmap with identical geometry + camera + eps on the same frame.
    _clipmap.level_world_cells = level_world_cells
    _clipmap.level_origins     = level_origins
    _clipmap.level_cells       = level_cells
    _clipmap.center_lattice    = center_lattice
    _clipmap.half0             = half0
    _clipmap.camera_lattice    = camera_lattice
    _clipmap.proj              = proj
    _clipmap.eps_px            = eps_px
    _clipmap.error_driven      = error_driven
    _clipmap.uniform_core      = uniform_core
    if dump_next:
        _arm_dump(center_lattice, camera_lattice, half0, proj, root_origin)
    # An immutable snapshot of the sparse store for the worker (cheap — copies only edited
    # nodes; unedited world stays the on-demand generator).
    var job_store: EditStore = _edit_store.duplicate()
    _task_id = WorkerThreadPool.add_task(
        _mesh_job.bind(job_store, level_world_cells, level_origins, level_cells, center_lattice, half0,
            camera_lattice, proj, eps_px, error_driven, uniform_core, root_origin,
            MaterialPalette.colors()), false, "DC terrain mesh")


# Runs on a worker thread: read each clipmap level from the (immutable) store snapshot, then
# build + mesh one octree over them with the C++ DCOctreeMesher. Pure computation over the
# snapshot + immutable PackedArrays — safe off the main thread (no Node / engine access).
func _mesh_job(store: EditStore, level_world_cells: PackedVector3Array,
        level_origins: PackedVector3Array, level_cells: PackedFloat32Array,
        center: Vector3, half0: float, camera: Vector3, proj: float, eps: float, err: bool,
        uniform: bool, world_origin: Vector3i, palette: PackedColorArray) -> void:
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
    _job.arrays = _mesher.mesh_clipmap(
        level_data, LEVEL_DIM, level_origins, level_cells, center, half0, _ROOT_DEPTH,
        camera, proj, eps, err, world_origin, level_indices, palette,
        uniform,  # uniform_core: KEEP the fine core (level 0) at 1m so edits near the player splice
                  # with a small box. `dccore off` drops it (the core coarsens too — uniform huge
                  # triangles at high eps, but edits there may crack / force a full rebuild).
        0.0)    # surface-sparse prune DISABLED: the local-gradient bound is unreliable on
                # godot_voxel's lossy-encoded + geomorph-blended multi-level SDF (it over-prunes
                # real surface -> big slivers). Safe at lod 0 only; needs a mip-robust bound.
    _job.owners      = _mesher.get_last_triangle_owners()
    _job.sizes = _mesher.get_last_triangle_owner_sizes()


# Diagnostic (dcdump): write this dispatch's mesher INPUT (clipmap SDF + params) paired
# with the OUTPUT mesh it produced, so the exact case can be replayed and audited
# headlessly — and the displayed mesh inspected directly (Mesh.ARRAY_* arrays).
func _arm_dump(center: Vector3, camera: Vector3, half0: float, proj: float, root_origin: Vector3i) -> void:
    dump_next = false
    _dump_armed = true
    # level_data / origins / cells are filled in by _mesh_job once the worker reads the store.
    _dump_dict = {
        "dim": LEVEL_DIM,
        "center": center, "half0": half0, "depth": _ROOT_DEPTH,
        "camera": camera, "proj": proj, "eps_px": eps_px, "err": error_driven, "root_origin": root_origin,
    }


func _dump_write() -> void:
    _dump_armed = false
    _dump_dict["mesh"] = _job.arrays
    _dump_dict["mesh_origin"] = _job.origin
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

    if _job.arrays.is_empty():
        _mesh_instance.mesh = null
        _edits_during_build.clear()
        return

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _job.arrays)
    _mesh_instance.mesh = mesh
    _mesh_instance.global_position = Vector3(_job.origin) * VoxelConstants.RENDER_BASE_CELL   # base-cell origin -> world
    _cache.arrays      = _job.arrays       # this full build is now the splice base
    _cache.owners      = _job.owners
    _cache.sizes = _job.sizes
    _cache.origin      = _job.origin

    if log_timings or Perf.is_shown():
        var verts: int = (_job.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
        var ms := Time.get_ticks_msec() - _build_t0
        print("DC FULL rebuild: %d verts — %d ms (worker, all %d LOD levels)" % [verts, ms, LEVELS])
        if Perf.is_shown():
            Toast.show_message("FULL rebuild %d ms (%d verts)" % [ms, verts], Color(1.0, 0.7, 0.4))

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
