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
const OVERLAY_DIM       := 65      # edit-overlay box read from godot_voxel: 64 m span around the player
const OVERLAY_HALF      := 32      # OVERLAY_DIM / 2 — the box's half-extent in cells
# Perf note: each recenter rebuilds the whole octree from the noise (the sign-agreement
# homogeneity test samples TerrainField ~9x per node), so it's seconds at 512 m and
# sub-second at 256 m — fine off-thread for a diagnostic, but the real fix for a default
# render is incremental re-imprint (only the margin the player crossed), a later bite.

var _follow:  Node3D
var _terrain: VoxelLodTerrain   # null = generator-only (no edit overlay)
var _reader:  DCRegionReader
var _enabled := false

var _task_id := -1
var _job_octree: SparseVoxelOctree
var _job_overlay: Dictionary = {}   # {data, origin} read on the main thread for the worker
var _job_arrays: Array = []
var _last_center := Vector3.INF


# `terrain` lets the preview stay edit-aware: each build re-reads a box around the player
# from godot_voxel's edited store and overlays it on the generator, so digs/builds show.
# Without it, the preview is the pure generator.
func setup(follow: Node3D, terrain: VoxelLodTerrain = null) -> void:
    _follow = follow
    _terrain = terrain
    if _terrain != null:
        _reader = DCRegionReader.new()
        VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_terrain_edit)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.25, 0.85, 1.0)
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
    material_override = mat
    visible = false


# An edit re-reads the world, so rebuild at the next frame to pick it up.
func _on_terrain_edit(_event: VoxelEvent) -> void:
    if _enabled:
        _last_center = Vector3.INF


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


# Build the octree shell + read the edit overlay on the main thread (object creation and
# the godot_voxel read must not happen off-thread), then imprint + mesh on a worker (pure
# C++ data work — no Node / RenderingServer access).
func _dispatch(center: Vector3) -> void:
    _last_center = center
    _job_overlay = _read_overlay(center)
    _job_octree = SparseVoxelOctree.new()
    _job_octree.setup(center - Vector3.ONE * (ROOT_SIZE * 0.5), ROOT_SIZE)
    _task_id = WorkerThreadPool.add_task(_mesh_job.bind(center), false, "substrate octree mesh")


func _mesh_job(center: Vector3) -> void:
    _imprint(_job_octree, center, _job_overlay)
    _job_arrays = _job_octree.mesh()


# Read a box around the focus from godot_voxel's edited store (generator baseline + edits),
# LOD0 so it's fine. Empty when there's no terrain (generator-only preview). Main thread.
func _read_overlay(center: Vector3) -> Dictionary:
    if _terrain == null:
        return {}
    var origin := Vector3i(center.floor()) - Vector3i.ONE * OVERLAY_HALF
    var data := _reader.read_sdf_lod(_terrain, 0, origin, Vector3i.ONE * OVERLAY_DIM)
    return {"data": data, "origin": Vector3(origin)}


func _imprint(octree: SparseVoxelOctree, center: Vector3, overlay: Dictionary) -> void:
    if overlay.is_empty():
        octree.imprint_terrain_graded(center, NEAR_LEAF, BAND, BASE, AMP, PERIOD, OCTAVES, SEED)
    else:
        octree.imprint_terrain_overlay_graded(center, NEAR_LEAF, BAND, BASE, AMP, PERIOD, OCTAVES, SEED,
            overlay.data, OVERLAY_DIM, overlay.origin, 1.0)


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
    var center := _follow.global_position
    var octree := SparseVoxelOctree.new()
    octree.setup(center - Vector3.ONE * (ROOT_SIZE * 0.5), ROOT_SIZE)
    _imprint(octree, center, _read_overlay(center))
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
