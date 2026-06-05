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
# Meshes a distance-graded bubble: finest cells near the follow target, coarsening
# with distance. OctreeDC's point-location meshing stitches the level transitions
# crack-free with no balance pass needed.

const ROOT_DEPTH        := 6      # 2^6 = 64-voxel root cube around the follow target
const RECENTER_DISTANCE := 8.0    # re-mesh once the follow target drifts this far (m)
const LOD_QUALITY       := 6.0    # target cell size ~= distance / this (smaller = finer farther out)

var _terrain: VoxelLodTerrain
var _follow:  Node3D

var _mesh_instance: MeshInstance3D
var _enabled := false

var _task_id := -1
var _job_origin: Vector3i
var _job_arrays: Array = []
var _last_center := Vector3.INF


func setup(terrain: VoxelLodTerrain, follow: Node3D) -> void:
    _terrain = terrain
    _follow  = follow
    _mesh_instance = MeshInstance3D.new()
    var mat := StandardMaterial3D.new()
    mat.albedo_color  = Color(0.2, 1.0, 1.0, 0.55)
    mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.cull_mode     = BaseMaterial3D.CULL_DISABLED
    _mesh_instance.material_override = mat
    add_child(_mesh_instance)


func set_enabled(on: bool) -> void:
    _enabled = on
    if on:
        _last_center = Vector3.INF   # force an immediate re-mesh on next tick
    else:
        _mesh_instance.mesh = null


func is_enabled() -> bool:
    return _enabled


func _process(_dt: float) -> void:
    if not _enabled or _follow == null:
        return
    if _task_id != -1:
        if WorkerThreadPool.is_task_completed(_task_id):
            _finish()
        return
    var center := _follow.global_position
    if center.distance_to(_last_center) > RECENTER_DISTANCE:
        _dispatch(center)


func _dispatch(center: Vector3) -> void:
    var size   := 1 << ROOT_DEPTH
    var origin := Vector3i(center.round()) - Vector3i(size / 2, size / 2, size / 2)
    var dim    := size + 1                       # corner samples
    var data   := DCRegionReader.new().read_sdf_lod0(_terrain, origin, Vector3i(dim, dim, dim))
    if data.size() != dim * dim * dim:
        return
    var baked := SdfBaked.new(data, Vector3.ZERO, 1.0, Vector3i(dim, dim, dim))
    # Subdivide finer the closer a cell is to the follow target (in the octree's
    # local space, where the target sits at the bubble centre). Captures values by
    # copy — no self/Node reference — so it's safe to call on the worker thread.
    var focus := center - Vector3(origin)
    var inv_quality := 1.0 / LOD_QUALITY
    var refine := func(c: Vector3, s: float, _d: int) -> bool:
        return s > c.distance_to(focus) * inv_quality
    _job_origin  = origin
    _job_arrays  = []
    _last_center = center
    _task_id = WorkerThreadPool.add_task(_mesh_job.bind(baked, refine), false, "DC terrain mesh")


# Runs on a worker thread: pure CPU over the immutable baked field.
func _mesh_job(baked: SdfBaked, refine: Callable) -> void:
    _job_arrays = OctreeDC.build_field_arrays(baked, ROOT_DEPTH, refine)


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


func _exit_tree() -> void:
    # Don't let the pool run our callable into a freed object.
    if _task_id != -1:
        WorkerThreadPool.wait_for_task_completion(_task_id)
        _task_id = -1
