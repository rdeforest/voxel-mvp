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

const DEPTH        := 13      # root = 2^13 = 8192-unit cube (2048 m at 0.25); the window roams inside it
const ROOT_SIZE    := 1 << DEPTH  #   (size is free — cells outside the window are cheap absent leaves)
const ROOT_SNAP    := 64      # snap the root origin to this LATTICE grid (cells stay world-aligned)
const RECENTER     := 6.0     # re-mesh once the player drifts this far (m)

# Budget controller (doc 13 B2): ONE knob, _eps_px, driven against two costs. Start coarse (cheap) and
# tighten until either binds. Mesh lag = the worker build's WORK ms (terrain latency); frame time = render.
const EPS_START    := 48.0    # start with a big error allowance (coarse) — the controller tightens it
const EPS_MIN      := 1.0
const EPS_MAX      := 256.0
var frame_budget := 16.0      # ms — frame-gen (render) budget; the `dcframebudget` console knob. Refine while
                              # render cost < half this, back off above it. Generous default — not an FPS game.

var mesh_ceil   := 500.0  # ms — over this mesh lag: coarsen (raise eps). The `meshlag` console knob.
var mesh_target := 100.0  # ms — under this (and frame headroom): refine (lower eps). Scales with the ceiling.

var base_cell    := VoxelConstants.RENDER_BASE_CELL  # metres per lattice unit (matches production density)
var win_radius_m := 128.0                            # resident window half-extent (m) — graded floor + budget make it affordable
var _eps_px      := EPS_START                        # the single operating point; floor + collapse both derive from it
var _frame_ms    := 0.0                              # smoothed frame time (render-cost signal)
var _eps_dirty   := false                            # the controller changed eps → re-mesh to apply it

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
var _job_cam := Vector3.ZERO
var _job_proj := 0.0
var _job_eps := EPS_START            # eps captured for the in-flight job
var _job_is_grow := false            # in-flight job is an incremental grow (vs a full build)
var _job_win_min := Vector3i.ZERO
var _job_win_max := Vector3i.ZERO
var _job_work_ms := 0.0              # worker build time of the last job = mesh lag (controller signal)
var _palette: PackedColorArray      # material id → albedo (per-vertex colours), like the clipmap render
var _inval: Node3D                  # the invalidation overlay (dcinval) — fed the LOD diagnostic

# dcinval diagnostic thresholds: a triangle whose owner cell projects to more than LARGE×eps px is
# under-resolved (chunky); less than SMALL×eps is over-resolved (wasteful). Relative to the live eps_px.
const DIAG_LARGE_MULT := 8.0
const DIAG_SMALL_MULT := 0.5

func setup(follow: Node3D, edit_store: EditStore = null) -> void:
    _follow = follow
    _edit_store = edit_store
    if _edit_store != null:
        VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_terrain_edit)
    material_override = load(VoxelConstants.TERRAIN_MATERIAL_PATH)   # the production terrain shader (dcworld is the render now)
    _palette = MaterialPalette.colors()              # per-vertex material colours (placed parts read their material)
    # Parallel leaf sampling. Capped at 8: the build's serial tree-walk (structure + QEF roll-up) is the
    # Amdahl ceiling (~4-5x), so more threads buy ~nothing and just hog cores. `dcthreads` overrides for tuning.
    _mesher.set_thread_count(mini(OS.get_processor_count(), 8))
    visible = false


func _on_terrain_edit(_event: VoxelEvent) -> void:
    if _enabled:
        _dirty = true   # grow only samples NEW cells; an edit in the interior needs a full rebuild


func is_enabled() -> bool:
    return _enabled


func set_diagnostic_overlay(overlay: Node3D) -> void:
    _inval = overlay


# Recompute the dcinval LOD diagnostic from the last mesh (called on mesh-apply and when dcinval turns on).
func refresh_diagnostic() -> void:
    if _inval != null and _inval.is_enabled() and _task_id == -1:
        _emit_diagnostic()


# Flag triangles whose owner cell projects off-target on screen: too big (under-resolved) or too small
# (over-resolved) vs the live eps_px. Pushes two world-space wireframe sets to the overlay (red / yellow).
func _emit_diagnostic() -> void:
    if _job_arrays.is_empty():
        _inval.set_diagnostic(PackedVector3Array(), PackedVector3Array())
        return
    var verts: PackedVector3Array = _job_arrays[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array = _job_arrays[Mesh.ARRAY_INDEX]
    var owners := _mesher.get_last_triangle_owners()
    var sizes := _mesher.get_last_triangle_owner_sizes()
    if owners.size() * 3 != idx.size():
        return # owner array doesn't match this mesh — skip rather than mis-map
    var ro := Vector3(_root_origin_i)
    var cam_world := (_job_cam + ro) * base_cell
    var big := PackedVector3Array()
    var small := PackedVector3Array()
    var t := 0
    for base in range(0, idx.size(), 3):
        var s_world: float = sizes[t] * base_cell
        var center_world: Vector3 = (owners[t] + Vector3.ONE * (sizes[t] * 0.5)) * base_cell
        var d := maxf(center_world.distance_to(cam_world), 0.001)
        var px := s_world * _job_proj / d
        if px > _job_eps * DIAG_LARGE_MULT or px < _job_eps * DIAG_SMALL_MULT:
            var a := (ro + verts[idx[base]]) * base_cell
            var b := (ro + verts[idx[base + 1]]) * base_cell
            var c := (ro + verts[idx[base + 2]]) * base_cell
            if px > _job_eps * DIAG_LARGE_MULT:
                big.append(a); big.append(b); big.append(c)
            else:
                small.append(a); small.append(b); small.append(c)
        t += 1
    _inval.set_diagnostic(big, small)


# Tune the coverage radius live (the `dcworld <radius>` arg). Capped so the window fits inside the root with
# a re-root margin (else the camera can never get far enough from a root face to roam — constant re-rooting).
# A change forces a rebuild next frame.
func set_radius(radius_m: float) -> void:
    # Cap so the window leaves ≥ ~96 m of roam before a re-root (roam = root/2 − radius − margin): a bigger
    # radius would re-root (full rebuild) almost every step. Bump DEPTH for more reach than this allows.
    var cap := ROOT_SIZE * base_cell * 0.5 - 128.0
    win_radius_m = clampf(radius_m, 2.0, cap)
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
    _frame_ms = lerpf(_frame_ms, Perf.frame_gen_ms(), 0.1)   # smoothed REAL frame-gen cost (render-cpu+GPU),
    # NOT the vsync/fps_max-capped dt — so the controller's frame-headroom gate sees true GPU load, not the
    # quantised display interval (a 144Hz vsync pins dt at ~6.9ms and only jumps at the fps cliff).
    Perf.status("dcworld", "eps_px %.1f   mesh-lag %.0f ms (%s)" % [_eps_px, _job_work_ms, "grow" if _job_is_grow else "build"])
    if _task_id != -1:
        if WorkerThreadPool.is_task_completed(_task_id):
            _finish()
        return
    var p := _follow.global_position
    # Full rebuild only when the field or frame changes: first build, an edit, or a re-root. A plain move or
    # an eps change (the controller re-grading) goes through grow_world — it re-meshes just the changed band
    # (P2.5 incremental band-diff), reusing the retained octree.
    if not _built or _dirty or _outside_root(p):
        _dispatch_build(p)
    elif p.distance_to(_last_center) > RECENTER or _eps_dirty:
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


# Full graded rebuild at a snapped root with a fresh EditStore snapshot. Captures the camera + window on
# the MAIN thread (the worker can't touch the viewport), then dispatches the build to a worker.
func _dispatch_build(p: Vector3) -> void:
    _root_origin_i = _snap_root(p)
    _job_store = _edit_store.duplicate() if _edit_store != null else null
    _built = true
    _dirty = false
    _eps_dirty = false
    _last_center = p
    var win := _window(p)
    _job_win_min = win[0]
    _job_win_max = win[1]
    _job_cam = _camera_lattice()
    _job_proj = _view_proj()
    _job_eps = _eps_px                            # capture the operating point for the worker
    _job_is_grow = false
    _task_id = WorkerThreadPool.add_task(_run_job, false, "dcworld build")


# Incremental move: grow_world re-meshes only the band the move/eps change touched, reusing the retained
# octree (same root, no new store snapshot — grow reads the retained snapshot). The common path while walking.
func _dispatch_grow(p: Vector3) -> void:
    _eps_dirty = false
    _last_center = p
    var win := _window(p)
    _job_win_min = win[0]
    _job_win_max = win[1]
    _job_cam = _camera_lattice()
    _job_proj = _view_proj()
    _job_eps = _eps_px
    _job_is_grow = true
    _task_id = WorkerThreadPool.add_task(_run_job, false, "dcworld grow")


func _run_job() -> void:
    var t0 := Time.get_ticks_usec()
    if _job_is_grow:
        _job_arrays = _mesher.grow_world(_job_cam, _job_proj, _job_eps, _job_win_min, _job_win_max)
    else:
        _job_arrays = _mesher.mesh_world(_job_store, _root_origin_i, DEPTH, base_cell,
                _job_cam, _job_proj, _job_eps, true, _palette, _job_win_min, _job_win_max)
    _job_work_ms = (Time.get_ticks_usec() - t0) / 1000.0   # mesh lag = the controller's primary signal


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
    if _inval != null and _inval.is_enabled():
        _emit_diagnostic()   # refresh the dcinval LOD overlay for this mesh
    _control()


# The B2 budget controller (doc 13): nudge the one knob, _eps_px, toward the budget. Coarsen (raise eps) if
# mesh lag or frame time is over budget; refine (lower eps) only when BOTH have headroom. Damped, and it
# backs off (×1.4) faster than it refines (×0.9). A change marks _eps_dirty → re-mesh applies it; in the
# comfort band eps stops moving, so tuning rebuilds stop. The floor + collapse both derive from _eps_px.
func _control() -> void:
    var prev := _eps_px
    var over := _job_work_ms > mesh_ceil or _frame_ms > frame_budget
    var under := _job_work_ms < mesh_target and _frame_ms < frame_budget * 0.5
    if over:
        _eps_px = minf(_eps_px * 1.4, EPS_MAX)
    elif under:
        _eps_px = maxf(_eps_px * 0.9, EPS_MIN)
    _eps_dirty = absf(_eps_px - prev) > 0.01


# `meshlag` console knob: set the mesh-lag ceiling (ms) the controller keeps eps under; the refine target
# scales with it (1/5, so 500→100). Higher = more detail at the cost of slower re-mesh on a move.
func set_max_lag(ms: float) -> void:
    mesh_ceil = maxf(50.0, ms)
    mesh_target = mesh_ceil * 0.2
    _eps_dirty = true   # kick the controller to re-tune toward the new budget even while stationary


func set_frame_budget(ms: float) -> void:
    frame_budget = maxf(1.0, ms)
    _eps_dirty = true   # kick the controller to re-tune toward the new budget even while stationary


func _arrays_to_mesh(arrays: Array) -> ArrayMesh:
    var m := ArrayMesh.new()
    if not arrays.is_empty() and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
        m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return m


func set_mesh_threads(n: int) -> void:
    _mesher.set_thread_count(n)


# Force a full rebuild on the next frame (re-bake + build + collapse) — the heavy path, for timing
# experiments via the console without having to walk. _process picks up _dirty and dispatches a build.
func force_rebuild() -> void:
    _dirty = true


func mesh_phase_report() -> String:
    return "threads %d | last build: accel %.0f + build %.0f + collapse %.0f ms" % [
        _mesher.get_thread_count(),
        _mesher.get_last_accel_ms(),
        _mesher.get_last_build_ms(),
        _mesher.get_last_collapse_ms()]


func _exit_tree() -> void:
    if _task_id != -1:
        WorkerThreadPool.wait_for_task_completion(_task_id)
        _task_id = -1
