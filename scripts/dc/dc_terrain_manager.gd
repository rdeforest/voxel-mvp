class_name DCTerrainManager
extends Node3D

# F2 path-b #3: our own meshing/render layer over godot_voxel's data. Meshes a
# cube of terrain around the followed node (the player) with OctreeDC and renders
# our mesh, re-meshing as the player moves. godot_voxel stays the data / stream /
# edit / collision engine; this only reads and renders.
#
# Threading: the region read (DCRegionReader, bulk locked C++ copy) and the bake
# happen on the main thread (~0ms with cache_generated_blocks on). The expensive
# OctreeDC pass runs on a WorkerThreadPool task over an immutable SdfBaked, so it
# never hitches the frame and never touches a Node or the engine store from the
# thread. The finished arrays come back and the ArrayMesh is built on the main
# thread (RenderingServer upload).
#
# Meshes a distance-graded LOD clipmap: nested levels centred on the follow target,
# level k covering 2^k the extent at 2^k the cell size, each read at LOD k so coarse
# cells sample coarse data (no undersampling). One octree spans the whole clipmap;
# the refine matches cell size to the clipmap level so data LOD and cell size
# transition together. OctreeDC's point-location meshing stitches it crack-free with
# no balance pass needed. See SdfClipmap.

const LEVELS            := 6      # LOD levels (0..5): 1024m coverage (32m fine core)
const LEVEL_DIM         := 33     # samples per axis per level; LEVEL_DIM-1 must be a power of 2
const RECENTER_DISTANCE := 8.0    # re-mesh once the follow target drifts this far (m)

# Derived: octree root spans the coarsest level. ROOT = (LEVEL_DIM-1) << (LEVELS-1).
const _LEVEL_CELLS      := LEVEL_DIM - 1                 # 32
const _ROOT_DEPTH       := 5 + LEVELS - 1                # log2(32) + (LEVELS-1)
const _COARSEST_CELL    := 1 << (LEVELS - 1)             # snap granularity

var _terrain: VoxelLodTerrain
var _follow:  Node3D

var _mesh_instance: MeshInstance3D
var _enabled := false

var _data_only := false
var _saved_render_mask := 1      # godot_voxel's render layers before we hid them
var _pending_data_only := false  # hide godot_voxel once our first mesh lands (no startup void)
var _debug_material: Material    # translucent cyan, used only in debug-overlay mode

var _task_id := -1
var _job_origin: Vector3i
var _job_arrays: Array = []
var _last_center := Vector3.INF
var _job_read_ms := 0
var _job_t0 := 0

# Print per-recenter read/mesh timings to the output (tuning aid). Only fires while
# the manager is enabled, which is opt-in, so it's quiet in normal play.
var log_timings := true


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


func _on_terrain_edit(_event: TerrainSdfChangedEvent) -> void:
    _last_center = Vector3.INF   # force a re-mesh so the edit shows next tick


func _process(_dt: float) -> void:
    if not _enabled or _follow == null:
        return
    var t0 := Time.get_ticks_usec()
    if _task_id != -1:
        if WorkerThreadPool.is_task_completed(_task_id):
            _finish()
    else:
        var center := _follow.global_position
        if center.distance_to(_last_center) > RECENTER_DISTANCE:
            _dispatch(center)
    Perf.report("DC mesh (main)", (Time.get_ticks_usec() - t0) / 1000.0)


func _dispatch(center: Vector3) -> void:
    var root_size := 1 << _ROOT_DEPTH                       # world extent of the coarsest level
    # Snap the centre to the coarsest cell so every level's read origin lands on its
    # own LOD grid (floor-snap, so it's stable across the world origin).
    var snapped := Vector3i((center / float(_COARSEST_CELL)).floor()) * _COARSEST_CELL
    var root_origin := snapped - Vector3i(root_size / 2, root_size / 2, root_size / 2)
    var center_lattice := Vector3.ONE * (root_size / 2)     # follow target, lattice space
    var dim_v := Vector3i(LEVEL_DIM, LEVEL_DIM, LEVEL_DIM)
    var read_t0 := Time.get_ticks_msec()
    var reader := DCRegionReader.new()
    # Parallel arrays describing the clipmap levels for the C++ mesher: per level k,
    # the SDF data, its lattice origin, and its cell size (LOD k = 2^k).
    var level_data: Array = []
    var level_origins := PackedVector3Array()
    var level_cells := PackedFloat32Array()
    for k in LEVELS:
        var cell := 1 << k
        var half_k := (_LEVEL_CELLS / 2) << k               # lattice half-extent of level k
        var lattice_origin := Vector3i(root_size / 2 - half_k, root_size / 2 - half_k, root_size / 2 - half_k)
        var world_origin := root_origin + lattice_origin
        var data := reader.read_sdf_lod(_terrain, k, world_origin, dim_v)
        if data.size() != LEVEL_DIM * LEVEL_DIM * LEVEL_DIM:
            return                                          # incomplete read; try again next tick
        level_data.append(data)
        level_origins.append(Vector3(lattice_origin))
        level_cells.append(float(cell))
    _job_read_ms = Time.get_ticks_msec() - read_t0
    _job_t0      = Time.get_ticks_msec()
    _job_origin  = root_origin
    _job_arrays  = []
    _last_center = center
    var half0 := float(_LEVEL_CELLS) * 0.5
    _task_id = WorkerThreadPool.add_task(
        _mesh_job.bind(level_data, level_origins, level_cells, center_lattice, half0), false, "DC terrain mesh")


# Runs on a worker thread: the C++ DCOctreeMesher builds + meshes one octree over
# the clipmap. Pure computation over immutable PackedArrays — safe off the main
# thread (no Node / engine access).
func _mesh_job(level_data: Array, level_origins: PackedVector3Array, level_cells: PackedFloat32Array,
        center: Vector3, half0: float) -> void:
    _job_arrays = DCOctreeMesher.new().mesh_clipmap(
        level_data, LEVEL_DIM, level_origins, level_cells, center, half0, _ROOT_DEPTH)


func _finish() -> void:
    WorkerThreadPool.wait_for_task_completion(_task_id)
    _task_id = -1
    if _job_arrays.is_empty():
        _mesh_instance.mesh = null
        return
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _job_arrays)
    _mesh_instance.mesh = mesh
    _mesh_instance.global_position = Vector3(_job_origin)
    if _pending_data_only:
        _pending_data_only = false   # first mesh is up — now safe to hide godot_voxel
        set_data_only(true)
    if log_timings:
        var verts: int = (_job_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
        print("DC clipmap: %d verts — read %d ms (main), mesh %d ms (worker)" % [
            verts, _job_read_ms, Time.get_ticks_msec() - _job_t0])


func _exit_tree() -> void:
    # Don't let the pool run our callable into a freed object.
    if _task_id != -1:
        WorkerThreadPool.wait_for_task_completion(_task_id)
        _task_id = -1
    # Never leave godot_voxel's render hidden behind us.
    if is_instance_valid(_terrain):
        _terrain.render_layers_mask = _saved_render_mask
