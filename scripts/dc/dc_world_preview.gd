class_name DcWorldPreview
extends MeshInstance3D

# doc 16 THE GOAL, first GPU eyes: a live preview of the WORLD-FIXED incremental octree
# (DCOctreeMesher.mesh_world + grow_world), so the path we built headless can finally be
# judged on screen. A single persistent octree is anchored to fixed WORLD coordinates; the
# camera roams a resident WINDOW inside it. A move calls grow_world — graft the leading edge,
# evict the trailing edge, re-collapse by screen-error — reusing the interior. A re-root
# (player nears the root face) or an edit calls mesh_world (full window build). Build + grow
# run on a WorkerThreadPool task (pure C++, no Node/RenderingServer); the ArrayMesh swap is
# on the main thread. `dcworld` toggles it. Shown amber, overlaid for comparison.
#
# DENSITY: base_cell defaults to RENDER_BASE_CELL (0.25 m) so the preview matches the live
# clipmap render's resolution. The build is DENSE to the floor, so 0.25 m costs 64× the cells
# of 1 m for the same metric bubble — hence the modest radius. That cost is exactly what the
# surface-sparse prune over direct sampling (doc 16 NEXT) removes; until then, coverage is a
# small BUBBLE around you with a hard rim where terrain stops (the window edge — NOT a bug).

const DEPTH        := 11      # root = 2^11 = 2048-unit cube; the window roams inside it (size is free —
const ROOT_SIZE    := 1 << DEPTH  #   cells outside the window are cheap absent leaves)
const ROOT_SNAP    := 64      # snap the root origin to this LATTICE grid (cells stay world-aligned)
const RECENTER     := 6.0     # grow the window once the player drifts this far (m)
const EPS_PX       := 2.0     # screen-error LOD threshold (px)

var base_cell    := VoxelConstants.RENDER_BASE_CELL  # metres per lattice unit (matches production density)
var win_radius_m := 12.0                             # resident window half-extent around the player (m)

var _follow:     Node3D
var _edit_store: EditStore        # live store; snapshotted per re-root so the worker reads immutably
var _enabled := false

var _mesher := DCOctreeMesher.new()  # persistent — holds the retained octree across frames
var _root_origin_i := Vector3i.ZERO  # LATTICE coords of the root's (0,0,0) corner
var _built := false
var _dirty := false                  # an edit happened → full rebuild to pick it up
var _last_center := Vector3.INF

var _task_id := -1
var _job_store: EditStore            # immutable snapshot handed to the worker
var _job_arrays: Array = []
var _job_is_grow := false
var _job_cam := Vector3.ZERO
var _job_proj := 0.0
var _job_win_min := Vector3i.ZERO
var _job_win_max := Vector3i.ZERO


func setup(follow: Node3D, edit_store: EditStore = null) -> void:
    _follow = follow
    _edit_store = edit_store
    if _edit_store != null:
        VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_terrain_edit)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.55, 0.1)
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    material_override = mat       # back-face cull ON (default): a crack reads as see-through
    visible = false


func _on_terrain_edit(_event: VoxelEvent) -> void:
    if _enabled:
        _dirty = true   # grow only samples NEW cells; an edit in the interior needs a full rebuild


func is_enabled() -> bool:
    return _enabled


# Tune the bubble live (the `dcworld <radius>` arg). A change forces a re-root next frame.
func set_radius(radius_m: float) -> void:
    win_radius_m = maxf(2.0, radius_m)
    _built = false


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
    elif p.distance_to(_last_center) > RECENTER:
        _dispatch_grow(p)


# Root origin (LATTICE) snapped to the ROOT_SNAP grid, centred on the player — cells never shift
# under a fixed feature, and re-roots land on stable boundaries.
func _snap_root(p: Vector3) -> Vector3i:
    var pl := p / base_cell                               # player in lattice units
    var o := ((pl - Vector3.ONE * (ROOT_SIZE * 0.5)) / ROOT_SNAP).floor() * ROOT_SNAP
    return Vector3i(o)


func _outside_root(p: Vector3) -> bool:
    var margin := win_radius_m + 32.0                     # re-root before the window can reach a root face
    var base := Vector3(_root_origin_i) * base_cell       # root corner in world metres
    var lo := base + Vector3.ONE * margin
    var hi := base + Vector3.ONE * (ROOT_SIZE * base_cell - margin)
    return p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z


# The resident window around the player, in WORLD LATTICE, clamped to the root box.
func _window(p: Vector3) -> Array:
    var r := int(ceil(win_radius_m / base_cell))          # radius in lattice units
    var c := Vector3i((p / base_cell).round())
    var lo := _root_origin_i
    var hi := _root_origin_i + Vector3i.ONE * ROOT_SIZE
    return [(c - Vector3i.ONE * r).clamp(lo, hi), (c + Vector3i.ONE * r).clamp(lo, hi)]


# px per world unit at unit distance (FOV + viewport height only). 0 with no camera.
func _view_proj() -> float:
    var cam := get_viewport().get_camera_3d()
    if cam == null:
        return 0.0
    var vp_h := float(get_viewport().get_visible_rect().size.y)
    return vp_h / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))


# Camera in the octree's lattice frame (world / base_cell − root origin), for screen-error collapse.
func _camera_lattice() -> Vector3:
    var cam := get_viewport().get_camera_3d()
    var cam_world := cam.global_position if cam != null else (_follow.global_position if _follow != null else Vector3.ZERO)
    return cam_world / base_cell - Vector3(_root_origin_i)


# Full rebuild at a snapped root with a fresh EditStore snapshot — re-root, edit, or first build.
func _dispatch_build(p: Vector3) -> void:
    _root_origin_i = _snap_root(p)
    _job_store = _edit_store.duplicate() if _edit_store != null else null
    _built = true
    _dirty = false
    _last_center = p
    _stage_job(p, false)


# Incremental: move the window toward the new position (graft leading edge, evict trailing) on the
# RETAINED octree — the common case as you walk. No new snapshot: grow reuses the retained store.
func _dispatch_grow(p: Vector3) -> void:
    _last_center = p
    _stage_job(p, true)


# Capture the camera + window on the MAIN thread (worker can't touch the viewport), then dispatch.
func _stage_job(p: Vector3, is_grow: bool) -> void:
    var win := _window(p)
    _job_win_min = win[0]
    _job_win_max = win[1]
    _job_cam = _camera_lattice()
    _job_proj = _view_proj()
    _job_is_grow = is_grow
    _task_id = WorkerThreadPool.add_task(_run_job, false, "dcworld grow" if is_grow else "dcworld build")


func _run_job() -> void:
    if _job_is_grow:
        _job_arrays = _mesher.grow_world(_job_cam, _job_proj, EPS_PX, _job_win_min, _job_win_max)
    else:
        _job_arrays = _mesher.mesh_world(_job_store, _root_origin_i, DEPTH, base_cell,
                _job_cam, _job_proj, EPS_PX, true, PackedColorArray(), _job_win_min, _job_win_max)


func _finish() -> void:
    WorkerThreadPool.wait_for_task_completion(_task_id)
    _task_id = -1
    if not _enabled:
        return
    var t0 := Time.get_ticks_usec()
    mesh = _arrays_to_mesh(_job_arrays)
    # mesh_world verts are lattice-local to the root corner; place + scale back to world metres.
    global_position = Vector3(_root_origin_i) * base_cell
    scale = Vector3.ONE * base_cell
    visible = true
    Perf.report("dcworld swap (main)", (Time.get_ticks_usec() - t0) / 1000.0)
    Perf.mark_event()


func _arrays_to_mesh(arrays: Array) -> ArrayMesh:
    var m := ArrayMesh.new()
    if not arrays.is_empty() and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
        m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return m


func _exit_tree() -> void:
    if _task_id != -1:
        WorkerThreadPool.wait_for_task_completion(_task_id)
        _task_id = -1
