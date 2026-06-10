class_name DcSubstratePreview
extends MeshInstance3D

# Phase B: a live preview of the store-over-generator substrate render, so it can be
# judged against the clipmap render while moving. Builds a SparseVoxelOctree from the
# analytic TerrainField (fine near the player, graded coarser out) and meshes it with
# DC, world-fixed and with NO camera input — so it's view-independent by construction
# (the property the camera-snapped clipmap can't have) and there are no mips, so no
# geomorph blend. Shown cyan, overlaid on the existing terrain for comparison.
#
# World-fixed + persistent + incremental: the octree's root is snapped to a world grid
# (so cells never shift — view-independent by construction), and it's kept across frames.
# Moving the player only REFINES the octree toward the new position (refine_terrain_graded
# adds detail at the leading margin — cheap); a full rebuild happens only when the player
# leaves the root (re-root) or an edit dirties it. The build/refine + mesh run on a
# WorkerThreadPool task (pure C++, no Node/RenderingServer); the ArrayMesh swap is on the
# main thread. Edit-aware: a box around the player is re-read from godot_voxel's store and
# overlaid on the generator, so digs/builds show. `dcgen` toggles it. Shown cyan, overlaid.
#
# NOT yet: the default render (it overlays the clipmap, not replaces it); collision and
# persistence still come from godot_voxel.

# Terrain params — mirror tools/build_terrain_graph.gd. The terrain function now lives in
# C++ (TerrainField); these are the tunables until the .tres graph retires with godot_voxel.
const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

const ROOT_SIZE         := 512.0   # world-fixed cube; bigger coverage is affordable now (refine, not rebuild)
const ROOT_SNAP         := 64.0    # snap the root origin to this world grid (cells stay world-aligned)
const ROOT_MARGIN       := 128.0   # re-root once the player is this close to the root's face
const NEAR_LEAF         := 1.0     # finest leaf at the focus
const BAND              := 32.0    # leaf size doubles every BAND metres from the focus
const RECENTER_DISTANCE := 16.0    # refine toward the player once they drift this far (m)
var _follow:  Node3D
var _edit_store: EditStore   # the live shadow store; snapshotted per build. null = pure generator
var _enabled := false

var _octree:      SparseVoxelOctree   # the persistent octree (built once per re-root, refined on move)
var _root_origin: Vector3
var _built  := false
var _dirty  := false                  # an edit happened — force a full rebuild

var _task_id := -1
var _job_store: EditStore   # immutable EditStore snapshot handed to the worker
var _job_arrays: Array = []
var _last_center := Vector3.INF


# `edit_store` makes the preview edit-aware: each build imprints the store's field
# (generator + ALL resident edits), so digs/builds show everywhere, not just near the
# player. Without it, the preview is the pure generator. An edit forces a rebuild.
func setup(follow: Node3D, edit_store: EditStore = null) -> void:
    _follow = follow
    _edit_store = edit_store
    if _edit_store != null:
        VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_terrain_edit)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.25, 0.85, 1.0)
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
    material_override = mat
    visible = false


# An edit changed the world, so the octree needs a full rebuild to pick it up (refine
# only ADDS generator detail — it doesn't re-read the edit overlay).
func _on_terrain_edit(_event: VoxelEvent) -> void:
    if _enabled:
        _dirty = true


func is_enabled() -> bool:
    return _enabled


func set_enabled(on: bool) -> void:
    _enabled = on
    if on:
        _built = false   # force a build next frame
    else:
        visible = false
        mesh = null


func _process(_dt: float) -> void:
    if not _enabled or _follow == null:
        return
    if _task_id != -1:
        if WorkerThreadPool.is_task_completed(_task_id):
            _finish()
        return
    var p := _follow.global_position
    if not _built or _dirty or _outside_root(p):
        _dispatch_build(p)
    elif p.distance_to(_last_center) > RECENTER_DISTANCE:
        _dispatch_refine(p)


# World-fixed root origin snapped to the ROOT_SNAP grid, centred on the player — so cells
# never shift under a fixed feature, and re-roots land on stable boundaries.
func _snap_root(p: Vector3) -> Vector3:
    return ((p - Vector3.ONE * (ROOT_SIZE * 0.5)) / ROOT_SNAP).floor() * ROOT_SNAP


func _outside_root(p: Vector3) -> bool:
    var lo := _root_origin + Vector3.ONE * ROOT_MARGIN
    var hi := _root_origin + Vector3.ONE * (ROOT_SIZE - ROOT_MARGIN)
    return p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z


# Full rebuild: fresh octree at a snapped root, an immutable EditStore snapshot taken on
# the main thread, then imprint + mesh on the worker. Runs on re-root, on an edit, and the
# first build.
func _dispatch_build(p: Vector3) -> void:
    _root_origin = _snap_root(p)
    _octree = SparseVoxelOctree.new()
    _octree.setup(_root_origin, ROOT_SIZE)
    _job_store = _edit_store.duplicate() if _edit_store != null else null
    _built = true
    _dirty = false
    _last_center = p
    _task_id = WorkerThreadPool.add_task(_build_job.bind(p), false, "substrate build")


# Incremental: refine the persistent octree toward the new position (cheap — only the
# leading margin), then re-mesh. The common case as you walk.
func _dispatch_refine(p: Vector3) -> void:
    _last_center = p
    _task_id = WorkerThreadPool.add_task(_refine_job.bind(p), false, "substrate refine")


func _build_job(p: Vector3) -> void:
    _imprint(_octree, _job_store, p)
    _job_arrays = _octree.mesh()


func _refine_job(p: Vector3) -> void:
    _octree.refine_terrain_graded(p, NEAR_LEAF, BAND, BASE, AMP, PERIOD, OCTAVES, SEED)
    _job_arrays = _octree.mesh()


# Imprint the octree from the EditStore's field (generator + all edits) when we have one,
# else the pure generator. `store` is the snapshot for the worker (or the live store on the
# sync rebuild path — same thread, no race).
func _imprint(octree: SparseVoxelOctree, store: EditStore, center: Vector3) -> void:
    if store != null:
        octree.imprint_store_graded(store, center, NEAR_LEAF, BAND)
    else:
        octree.imprint_terrain_graded(center, NEAR_LEAF, BAND, BASE, AMP, PERIOD, OCTAVES, SEED)


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
    _imprint(octree, _edit_store, center)   # sync, main thread — the live store is safe to read directly
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
