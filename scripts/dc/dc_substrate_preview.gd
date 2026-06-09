class_name DcSubstratePreview
extends MeshInstance3D

# Phase B: a live preview of the store-over-generator substrate render, so it can be
# judged against the clipmap render while moving. Builds a SparseVoxelOctree from the
# analytic TerrainField (fine near the player, graded coarser out) and meshes it with
# DC, world-fixed and with NO camera input — so it's view-independent by construction
# (the property the camera-snapped clipmap can't have) and there are no mips, so no
# geomorph blend. Shown cyan, overlaid on the existing terrain for comparison.
#
# Live + threaded: the octree build + mesh (pure C++, no Node / RenderingServer) runs on
# a WorkerThreadPool task, re-dispatched when the player drifts past RECENTER_DISTANCE;
# the ArrayMesh swap happens on the main thread when the task completes. Same lifecycle
# as DCTerrainManager. `dcgen` toggles it.
#
# NOT yet: edit-aware (digs/builds don't show — it's pure generator + grading), and it
# doesn't replace the clipmap as the default render. Those are the next bites.

# Terrain params — mirror tools/build_terrain_graph.gd. The terrain function now lives in
# C++ (TerrainField); these are the tunables until the .tres graph retires with godot_voxel.
const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

const ROOT_SIZE         := 256.0   # world cube spanning the preview, centred on the player
const NEAR_LEAF         := 1.0     # finest leaf at the focus
const BAND              := 24.0    # leaf size doubles every BAND metres from the focus
const RECENTER_DISTANCE := 16.0    # re-mesh once the player drifts this far (m)
# Perf note: each recenter rebuilds the whole octree from the noise (the sign-agreement
# homogeneity test samples TerrainField ~9x per node), so it's seconds at 512 m and
# sub-second at 256 m — fine off-thread for a diagnostic, but the real fix for a default
# render is incremental re-imprint (only the margin the player crossed), a later bite.

var _follow:  Node3D
var _enabled := false

var _task_id := -1
var _job_octree: SparseVoxelOctree
var _job_arrays: Array = []
var _last_center := Vector3.INF


func setup(follow: Node3D) -> void:
    _follow = follow
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.25, 0.85, 1.0)
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
    material_override = mat
    visible = false


func is_enabled() -> bool:
    return _enabled


func set_enabled(on: bool) -> void:
    _enabled = on
    if on:
        _last_center = Vector3.INF   # force an immediate (re)build at the current position
    else:
        visible = false
        mesh = null


func _process(_dt: float) -> void:
    if not _enabled or _follow == null:
        return
    if _task_id != -1:
        if WorkerThreadPool.is_task_completed(_task_id):
            _finish()
    elif _follow.global_position.distance_to(_last_center) > RECENTER_DISTANCE:
        _dispatch(_follow.global_position)


# Build the octree shell on the main thread (object creation), then imprint + mesh it on
# a worker (pure C++ data work — no Node / RenderingServer access).
func _dispatch(center: Vector3) -> void:
    _last_center = center
    _job_octree = SparseVoxelOctree.new()
    _job_octree.setup(center - Vector3.ONE * (ROOT_SIZE * 0.5), ROOT_SIZE)
    _task_id = WorkerThreadPool.add_task(_mesh_job.bind(center), false, "substrate octree mesh")


func _mesh_job(center: Vector3) -> void:
    _job_octree.imprint_terrain_graded(center, NEAR_LEAF, BAND, BASE, AMP, PERIOD, OCTAVES, SEED)
    _job_arrays = _job_octree.mesh()


func _finish() -> void:
    WorkerThreadPool.wait_for_task_completion(_task_id)
    _task_id = -1
    if not _enabled:
        return   # disabled mid-build — discard the result
    var t0 := Time.get_ticks_usec()
    mesh = _arrays_to_mesh(_job_arrays)
    global_position = Vector3.ZERO   # octree mesh vertices are already world-space
    visible = true
    Perf.report("substrate swap (main)", (Time.get_ticks_usec() - t0) / 1000.0)
    Perf.mark_event()


# Synchronous build at the follow target — used by tests and as a one-shot. Returns the
# triangle count (0 = the cube held no surface).
func rebuild() -> int:
    if _follow == null:
        return 0
    var octree := SparseVoxelOctree.new()
    var center := _follow.global_position
    octree.setup(center - Vector3.ONE * (ROOT_SIZE * 0.5), ROOT_SIZE)
    octree.imprint_terrain_graded(center, NEAR_LEAF, BAND, BASE, AMP, PERIOD, OCTAVES, SEED)
    var arrays := octree.mesh()
    mesh = _arrays_to_mesh(arrays)
    global_position = Vector3.ZERO
    visible = true
    var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
    @warning_ignore("integer_division")
    return idx.size() / 3


func clear() -> void:
    visible = false
    mesh = null


func _arrays_to_mesh(arrays: Array) -> ArrayMesh:
    var m := ArrayMesh.new()
    if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
        m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return m


func _exit_tree() -> void:
    if _task_id != -1:
        WorkerThreadPool.wait_for_task_completion(_task_id)
        _task_id = -1
