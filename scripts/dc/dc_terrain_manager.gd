class_name DCTerrainManager
extends Node3D

# Our own meshing/render layer over godot_voxel's data. Meshes a cube of terrain
# around the followed node (the player) with our C++ DCOctreeMesher and renders our
# mesh, re-meshing as the player moves. godot_voxel stays the data / stream / edit /
# collision engine; this only reads and renders.
#
# Threading: the region read (DCRegionReader, a bulk locked C++ copy) happens on the
# main thread (~0ms with cache_generated_blocks on). The expensive meshing pass
# (DCOctreeMesher) runs on a WorkerThreadPool task over immutable PackedFloat32Array
# levels, so it never hitches the frame and never touches a Node or the engine store
# from the thread. The finished arrays come back and the ArrayMesh is built on the
# main thread (RenderingServer upload).
#
# Meshes a distance-graded LOD clipmap: nested levels centred on the follow target,
# level k covering 2^k the extent at 2^k the cell size, each read at LOD k so coarse
# cells sample coarse data (no undersampling). One octree spans the whole clipmap;
# the refine matches cell size to the clipmap level so data LOD and cell size
# transition together. The mesher's point-location meshing stitches it crack-free
# with no balance pass needed.

const LEVELS            := 5      # LOD levels (0..4): 2048m coverage (128m fine core)
const LEVEL_DIM         := 129    # samples per axis per level; LEVEL_DIM-1 must be a power of 2
                                  # 129 -> ±64m of 1m cells, so dramatic 3D terrain (overhangs,
                                  # relief) renders fine instead of undersampling into floating
                                  # islands. ~8x the mesh compute of 65 (perf is fine until <30fps).
const RECENTER_DISTANCE := 8.0    # re-mesh once the follow target drifts this far (m)

# Derived: octree root spans the coarsest level. ROOT = (LEVEL_DIM-1) << (LEVELS-1).
const _LEVEL_CELLS      := LEVEL_DIM - 1                 # 128
const _ROOT_DEPTH       := 7 + LEVELS - 1                # log2(128) + (LEVELS-1)
const _COARSEST_CELL    := 1 << (LEVELS - 1)             # snap granularity (16m)

var _terrain: VoxelLodTerrain
var _follow:  Node3D

var _mesh_instance: MeshInstance3D
var _enabled := false

var _data_only := false
var _saved_render_mask := 1      # godot_voxel's render layers before we hid them
var _pending_data_only := false  # hide godot_voxel once our first mesh lands (no startup void)
var _debug_material: Material    # translucent cyan, used only in debug-overlay mode

var _mesher := DCOctreeMesher.new()   # reused: holds the persistent collapse-hysteresis state
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
const _EDIT_MARGIN := 3     # cells of slack around the edit box (covers the SDF influence)
const _EDIT_APRON  := 4     # cells built beyond the core for stitching the patch seam

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


func setup(terrain: VoxelLodTerrain, follow: Node3D) -> void:
    _terrain = terrain
    _follow  = follow
    _saved_render_mask = terrain.render_layers_mask
    _mesh_instance = MeshInstance3D.new()
    var debug_mat := StandardMaterial3D.new()
    debug_mat.albedo_color = Color(0.2, 1.0, 1.0, 0.55)
    debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    debug_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
    _debug_material = debug_mat
    add_child(_mesh_instance)
    _apply_render_swap()   # pick the initial mesh material (cyan until we're the default render)
    # Re-mesh on terrain edits too (not just movement), so digs/builds show even
    # with godot_voxel's render hidden. Bound method -> the bus weakrefs us and
    # auto-prunes on scene reload. v1 re-meshes the whole clipmap; incremental
    # (just the edited region) is a later optimization.
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_terrain_edit)


func set_enabled(on: bool) -> void:
    _enabled = on
    if on:
        _last_center = Vector3.INF   # force an immediate re-mesh on next tick
    else:
        _mesh_instance.mesh = null
    _apply_render_swap()


func is_enabled() -> bool:
    return _enabled

# Force a re-mesh on the next tick (after a live LOD-param change).
func remesh() -> void:
    _last_center = Vector3.INF


# Data-only mode: hide godot_voxel's own render (render_layers_mask = 0) so our DC
# mesh is what shows. Collision/data/streaming/edits stay live (collision is a
# separate static body, unaffected by the render mask). Only takes effect while
# the manager is enabled; disabling the manager restores godot_voxel's render.
func set_data_only(on: bool) -> void:
    _data_only = on
    _apply_render_swap()


func is_data_only() -> bool:
    return _data_only


# Make DC the default render: start meshing now, and hide godot_voxel's own render
# the moment our first mesh lands (so there's no startup gap where neither shows).
# The dcmanager / dcsolo console commands still override this by hand.
func start_default() -> void:
    _pending_data_only = true
    set_enabled(true)


func _apply_render_swap() -> void:
    if not is_instance_valid(_terrain):
        return
    var as_terrain := _data_only and _enabled
    _terrain.render_layers_mask = 0 if as_terrain else _saved_render_mask
    if _mesh_instance != null:
        # Default render: wear the terrain's real material (grass shader). Debug
        # overlay (dcmanager without dcsolo): translucent cyan over godot_voxel.
        _mesh_instance.material_override = _terrain.material if as_terrain else _debug_material


func _on_terrain_edit(event: TerrainSdfChangedEvent) -> void:
    # Incremental: re-mesh just the edited sub-box and splice it into the cached mesh, so a
    # dig shows in a frame instead of waiting on the ~5s full clipmap rebuild. Falls back to
    # a full re-mesh when the fast path can't apply.
    if not _enabled or _follow == null:
        return
    if not _try_splice_edit(event):
        _last_center = Vector3.INF   # fall back: full re-mesh next tick


# Re-mesh a small box around the edit (DCOctreeMesher.mesh_subregion) and swap its triangles
# for the cached mesh's in that box. Returns false (caller does a full re-mesh) when there's
# no cached base, a full job is in flight, or the edit is outside the uniform fine core.
func _try_splice_edit(event: TerrainSdfChangedEvent) -> bool:
    if _task_id != -1 or _cache_arrays.is_empty():
        return false
    var root_half := float(1 << _ROOT_DEPTH) * 0.5
    var fine_half := float(_LEVEL_CELLS) * 0.5 - float(_EDIT_MARGIN + _EDIT_APRON + 2)
    var off_center := (event.box_origin + event.box_size * 0.5) - (Vector3(_cache_origin) + Vector3.ONE * root_half)
    if maxf(absf(off_center.x), maxf(absf(off_center.y), absf(off_center.z))) > fine_half:
        return false   # outside the 1m fine core — the splice would meet coarse LOD; full re-mesh

    var core_min := Vector3i(event.box_origin.floor()) - Vector3i.ONE * _EDIT_MARGIN
    var core_max := Vector3i((event.box_origin + event.box_size).ceil()) + Vector3i.ONE * _EDIT_MARGIN
    var sub_origin := core_min - Vector3i.ONE * _EDIT_APRON
    var sub_hi := core_max + Vector3i.ONE * _EDIT_APRON
    var span := maxi(sub_hi.x - sub_origin.x, maxi(sub_hi.y - sub_origin.y, sub_hi.z - sub_origin.z))
    var sub_size := 1
    while sub_size < span:
        sub_size <<= 1
    var sub_dim := sub_size + 1

    var reader := DCRegionReader.new()
    var size_v := Vector3i(sub_dim, sub_dim, sub_dim)
    var sdf := reader.read_sdf_lod(_terrain, 0, sub_origin, size_v)
    if sdf.size() != sub_dim * sub_dim * sub_dim:
        return false
    var idx := reader.read_indices_lod(_terrain, 0, sub_origin, size_v)
    var patch := _mesher.mesh_subregion(sdf, sub_dim, Vector3.ZERO, 1.0,
        sub_origin, sub_size, core_min, core_max, idx, MaterialPalette.colors())
    _apply_splice(core_min, core_max, sub_origin, patch, _mesher.get_last_triangle_owners())
    return true


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
    Perf.report("DC mesh (main)", (Time.get_ticks_usec() - t0) / 1000.0)


# Integer halving of a non-negative size. The one spot that acknowledges the
# integer-division warning, so the call sites above read as plain arithmetic.
static func _half(n: int) -> int:
    @warning_ignore("integer_division")
    return n / 2


func _dispatch(center: Vector3) -> void:
    var root_size := 1 << _ROOT_DEPTH                       # world extent of the coarsest level
    # Snap the centre to the coarsest cell so every level's read origin lands on its
    # own LOD grid (floor-snap, so it's stable across the world origin).
    var snapped := Vector3i((center / float(_COARSEST_CELL)).floor()) * _COARSEST_CELL
    var root_origin := snapped - Vector3i.ONE * _half(root_size)
    var center_lattice := Vector3.ONE * _half(root_size)    # follow target, lattice space
    var dim_v := Vector3i(LEVEL_DIM, LEVEL_DIM, LEVEL_DIM)
    var read_t0 := Time.get_ticks_msec()
    var reader := DCRegionReader.new()
    # Parallel arrays describing the clipmap levels for the C++ mesher: per level k,
    # the SDF data, its lattice origin, and its cell size (LOD k = 2^k).
    var level_data: Array = []
    var level_indices: Array = []                           # per-level CHANNEL_INDICES (material ids)
    var level_origins := PackedVector3Array()
    var level_cells := PackedFloat32Array()
    for k in LEVELS:
        var cell := 1 << k
        var half_k := _half(_LEVEL_CELLS) << k              # lattice half-extent of level k
        var lattice_origin := Vector3i.ONE * (_half(root_size) - half_k)
        var world_origin := root_origin + lattice_origin
        var data := reader.read_sdf_lod(_terrain, k, world_origin, dim_v)
        if data.size() != LEVEL_DIM * LEVEL_DIM * LEVEL_DIM:
            return                                          # incomplete read; try again next tick
        level_data.append(data)
        level_indices.append(reader.read_indices_lod(_terrain, k, world_origin, dim_v))
        level_origins.append(Vector3(lattice_origin))
        level_cells.append(float(cell))
    _job_read_ms = Time.get_ticks_msec() - read_t0
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
        camera_lattice = cam.global_position - Vector3(root_origin)
        var vp_h := float(get_viewport().get_visible_rect().size.y)
        proj = vp_h / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
    if dump_next:
        _arm_dump(level_data, level_origins, level_cells, center_lattice, camera_lattice, half0, proj, root_origin)
    _task_id = WorkerThreadPool.add_task(
        _mesh_job.bind(level_data, level_origins, level_cells, center_lattice, half0,
            camera_lattice, proj, eps_px, error_driven, root_origin,
            level_indices, MaterialPalette.colors()), false, "DC terrain mesh")


# Runs on a worker thread: the C++ DCOctreeMesher builds + meshes one octree over
# the clipmap. Pure computation over immutable PackedArrays — safe off the main
# thread (no Node / engine access).
func _mesh_job(level_data: Array, level_origins: PackedVector3Array, level_cells: PackedFloat32Array,
        center: Vector3, half0: float, camera: Vector3, proj: float, eps: float, err: bool,
        world_origin: Vector3i, level_indices: Array, palette: PackedColorArray) -> void:
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
func _arm_dump(level_data: Array, origins: PackedVector3Array, cells: PackedFloat32Array,
        center: Vector3, camera: Vector3, half0: float, proj: float, root_origin: Vector3i) -> void:
    dump_next = false
    _dump_armed = true
    _dump_dict = {
        "level_data": level_data, "origins": origins, "cells": cells, "dim": LEVEL_DIM,
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
        return
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _job_arrays)
    _mesh_instance.mesh = mesh
    _mesh_instance.global_position = Vector3(_job_origin)
    _cache_arrays = _job_arrays           # this full build is now the splice base
    _cache_owners = _job_owners
    _cache_origin = _job_origin
    if _pending_data_only:
        _pending_data_only = false   # first mesh is up — now safe to hide godot_voxel
        set_data_only(true)
    if log_timings:
        var verts: int = (_job_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
        print("DC clipmap: %d verts — read %d ms (main), mesh %d ms (worker)" % [
            verts, _job_read_ms, Time.get_ticks_msec() - _job_t0])


# --- Debug audit: scan the CURRENTLY DISPLAYED mesh for bad triangles (dcaudit cmd) ---
# Reports degenerate (zero-area), sliver (high aspect), and tilted (facet normal far from
# its vertices' normals = a steep facet the grass shader paints dirt) triangles, in world
# coords, so a live anomaly can be located exactly. Pure observer — it reads the mesh
# that's on screen and does NOT re-mesh (a rebuild can mask a stale-mesh artifact).
func audit_current_mesh() -> void:
    if _mesh_instance == null or _mesh_instance.mesh == null or _mesh_instance.mesh.get_surface_count() == 0:
        print("dcaudit: no DC mesh on screen")
        return
    _audit(_mesh_instance.mesh.surface_get_arrays(0), Vector3i(_mesh_instance.global_position))

func _audit(arrays: Array, origin: Vector3i) -> void:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var o := Vector3(origin)
    var bad: Array = []
    for i in range(0, idx.size(), 3):
        var a := verts[idx[i]]; var b := verts[idx[i + 1]]; var c := verts[idx[i + 2]]
        var cross := (b - a).cross(c - a)
        var area := cross.length() * 0.5
        var le: float = maxf(maxf((b - a).length(), (c - b).length()), (a - c).length())
        var aspect := le * le / maxf(area, 1e-9)
        var dev := 0.0
        if area > 1e-6:
            var vn := (norms[idx[i]] + norms[idx[i + 1]] + norms[idx[i + 2]])
            if vn.length() > 1e-6:
                dev = rad_to_deg(acos(clampf(absf(cross.normalized().dot(vn.normalized())), 0.0, 1.0)))
        var degenerate := area < 1e-3
        var sliver := aspect > 80.0
        var tilted := dev > 35.0 and area >= 1e-3
        if degenerate or sliver or tilted:
            bad.append({"w": (a + b + c) / 3.0 + o, "area": area, "aspect": aspect, "dev": dev,
                "tag": ("degen" if degenerate else "sliver" if sliver else "tilted")})
    bad.sort_custom(func(x, y): return x["dev"] + (200.0 if x["aspect"] > 80 else 0.0) > y["dev"] + (200.0 if y["aspect"] > 80 else 0.0))
    print("dcaudit: %d suspect triangles of %d (origin %s)" % [bad.size(), idx.size() / 3, str(origin)])
    for i in mini(15, bad.size()):
        var t = bad[i]
        print("  [%s] world=%s  area=%.4f aspect=%.1f facet_vs_normals=%.1f deg" % [
            t["tag"], str(t["w"]), t["area"], t["aspect"], t["dev"]])


func _exit_tree() -> void:
    # Don't let the pool run our callable into a freed object.
    if _task_id != -1:
        WorkerThreadPool.wait_for_task_completion(_task_id)
        _task_id = -1
    # Never leave godot_voxel's render hidden behind us.
    if is_instance_valid(_terrain):
        _terrain.render_layers_mask = _saved_render_mask
