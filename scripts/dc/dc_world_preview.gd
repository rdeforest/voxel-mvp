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

# Budget controller (doc 13 B2 / doc 20): TWO decoupled loops. Loop B — eps tracks RENDER cost (frame time)
# only: the rendered triangle count is the one thing eps changes, so eps is driven by frame_gen_ms alone, and
# rises only when there are too many triangles to draw in budget. Loop A — the grow worker's REFINE rate is a
# wall-clock cap (refine_us). The worker is OFF the render thread, so its work ms must NOT drive eps — that was
# the old peg: a heavy retained-tree job (over the now-gone mesh-lag ceiling) drove eps to EPS_MAX even with
# the frame fine. Detail leaves the mesh only via the error gate; eps just sheds triangles when render is over.
const EPS_START    := 48.0    # start with a big error allowance (coarse, cheap first build) — the controller tightens it
const EPS_MIN      := 0.5     # finest min-error (px): the sharpest eps the controller drives toward when the frame has headroom
const EPS_MAX      := 256.0
var frame_budget := 16.0      # ms — frame-gen (render) budget; the `dcframebudget` console knob. Refine while
                              # render cost < half this, back off above it. Generous default — not an FPS game.

# C/P (doc 20): wall-clock cap (µs) on refine work per grow while blooming — "do as much as you can in X ms",
# worst-on-screen first. Each grow refines until this elapses then defers the rest (refine_pending drains it
# over frames), so the bloom spreads and per-job latency stays bounded. Self-tunes across hardware/scene where
# a fixed count can't. Tunable; `dcrefine` console knob.
var refine_us := 8000                 # per-grow refine budget (µs); `dcrefine` knob. With the incremental emit a
                                      # grow is O(refined), so this is just a latency target, not overhead to amortize.
var max_cells := 80_000_000           # memory budget: stop refining past this many octree cells (296 B each ≈
                                      # 24 GB). At LOG2=4 max-detail the arena would otherwise exhaust RAM. `dcmaxcells`.

# M (doc 20): residency extends this far (metres) beyond the VISIBLE window — kept resident + pre-baked so a
# turn or backtrack re-samples nothing, and the edge ahead is ready before you reach it. 0 = pre-M (residency
# == visible). Bounded cost (O(residency)); clamps to the root. Tunable; `dcretain` console knob.
var retain_margin_m := 128.0

var base_cell    := VoxelConstants.RENDER_BASE_CELL  # metres per lattice unit (matches production density)
var win_radius_m := 128.0                            # resident window half-extent (m) — graded floor + budget make it affordable
var _eps_px      := EPS_START                        # the single operating point; floor + collapse both derive from it
var _frame_ms    := 0.0                              # smoothed frame time (render-cost signal)
var _mem_status  := ""                               # M2: cells/RAM/arena readout, refreshed by the worker in _run_job
var _ram_throttle := 0                               # M2: the RAM-resident scan (mincore) is the costly part —
var _ram_gb := 0.0                                   # refresh it only every Nth job, not every job
var _eps_dirty   := false                            # the controller changed eps → re-mesh to apply it

var _follow:     Node3D
var _edit_store: EditStore        # live store; snapshotted per re-root so the worker reads immutably
var _enabled := false

var _mesher := DCOctreeMesher.new()  # persistent — holds the retained octree across frames
var _root_origin_i := Vector3i.ZERO  # LATTICE coords of the root's (0,0,0) corner
var _built := false
var _arena_checked := false          # M2: one-shot — did we pop the "arena not disk-backed" warning yet?
var _verify_tripped := false         # dcverify: one-shot Toast on the first bad emit (rest streams via REST)
var _dirty := false                  # an edit happened → full rebuild to pick it up
var _last_center := Vector3.INF

# Incremental edits (doc 20 E): when ON, a terrain edit re-meshes only its box via edit_world instead of a
# full rebuild. Default OFF — edit_world's localized result is still ~6% off a fresh build (doc 20 §E), so
# this is a DEBUG toggle (key I) for GPU-eyeing the artifact and the speed, not the default path yet.
var incremental_edits := false
var _pending_edit := false           # an incremental edit is queued (box accumulated in _edit_min/_max)
var _edit_min := Vector3i.ZERO       # accumulated edit box (WORLD LATTICE) since the last edit dispatch
var _edit_max := Vector3i.ZERO

var _task_id := -1
var _job_store: EditStore            # immutable snapshot handed to the worker
var _job_arrays: Array = []
var _job_mesh: ArrayMesh             # tier-2: the ArrayMesh built ON the worker thread (not in _finish)
var _job_cam := Vector3.ZERO
var _job_proj := 0.0
var _job_eps := EPS_START            # eps captured for the in-flight job
var _job_is_grow := false            # in-flight job is an incremental grow (vs a full build)
var _job_is_edit := false            # in-flight job is an incremental edit (edit_world)
var _job_refine_budget := -1         # C: refine budget captured for the worker (-1 = unbudgeted, on a move)
var _job_reuse := false               # c1: reuse the persistent frontier (pure drain) vs rebuild it (move/eps change)
var _refine_pending := false         # the last grow deferred refinement (budget hit) → keep draining at this eps
var _job_emit_min := Vector3i.ZERO   # M: visible window captured for the worker (residency = _job_win_min/max)
var _job_emit_max := Vector3i.ZERO
var _job_win_min := Vector3i.ZERO
var _job_win_max := Vector3i.ZERO
var _job_edit_min := Vector3i.ZERO   # edit box captured for the worker (WORLD LATTICE)
var _job_edit_max := Vector3i.ZERO
var _job_work_ms := 0.0              # worker build time of the last job = mesh lag (controller signal)
var _palette: PackedColorArray      # material id → albedo (per-vertex colours), like the clipmap render
var _inval: Node3D                  # the invalidation overlay (dcinval) — fed the LOD diagnostic

# dcinval = the refinement BACKLOG. A triangle's owner leaf carries a geometric error `we`; projected to pixels
# (we·proj/dist — the exact quantity collapse_test gates on) it exceeds eps precisely when the leaf is coarser
# than the surface there warrants — i.e. the worker still wants to sharpen it. Highlight leaves over LARGE×eps:
# the chunky-over-real-detail cells the worst-on-screen refiner works on next; they clear as it sharpens them.
# Flat ground reads ~0 error so it never shows. No over-resolved pass — max detail is the goal, not the enemy.
const DIAG_LARGE_MULT := 2.0

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


func _on_terrain_edit(event: VoxelEvent) -> void:
    if not _enabled:
        return
    if incremental_edits and event is TerrainSdfChangedEvent:
        _accumulate_edit_box(event)   # re-mesh only this box via edit_world (doc 20 E)
    else:
        _dirty = true   # default: grow only samples NEW cells, so an interior edit needs a full rebuild


# Union the edit's world-metre box into the pending edit box, in WORLD LATTICE (world / base_cell). The
# worker re-meshes the union once dispatched, so several edits in one frame coalesce into one edit_world.
func _accumulate_edit_box(e: TerrainSdfChangedEvent) -> void:
    var lo := Vector3i((e.box_origin / base_cell).floor())
    var hi := Vector3i(((e.box_origin + e.box_size) / base_cell).ceil())
    if _pending_edit:
        _edit_min = _edit_min.min(lo)
        _edit_max = _edit_max.max(hi)
    else:
        _edit_min = lo
        _edit_max = hi
        _pending_edit = true


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
    var errors := _mesher.get_last_triangle_owner_errors()
    if owners.size() * 3 != idx.size() or errors.size() != owners.size():
        return # owner array doesn't match this mesh — skip rather than mis-map
    var ro := Vector3(_root_origin_i)
    var cam_world := (_job_cam + ro) * base_cell
    var backlog := PackedVector3Array()
    var t := 0
    for base in range(0, idx.size(), 3):
        var we_world: float = errors[t] * base_cell   # owner leaf's geometric error in metres
        var center_world: Vector3 = (owners[t] + Vector3.ONE * (sizes[t] * 0.5)) * base_cell
        var d := maxf(center_world.distance_to(cam_world), 0.001)
        var px := we_world * _job_proj / d            # error projected to pixels — collapse_test's own metric
        if px > _job_eps * DIAG_LARGE_MULT:           # coarser than warranted → still in the refine backlog
            backlog.append((ro + verts[idx[base]]) * base_cell)
            backlog.append((ro + verts[idx[base + 1]]) * base_cell)
            backlog.append((ro + verts[idx[base + 2]]) * base_cell)
        t += 1
    _inval.set_diagnostic(backlog, PackedVector3Array())


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
    Perf.status("dcworld", "eps_px %.1f   job %.0f ms (%s%s)" % [_eps_px, _job_work_ms, _job_kind(), " refining" if _refine_pending else ""])
    Perf.status("dcmem", _mem_status)   # computed on the worker in _run_job (race-free, off the main thread)
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
    elif _pending_edit:
        _dispatch_edit(p)
    elif p.distance_to(_last_center) > RECENTER:
        # Move: always re-window (graft new coverage at the floor, evict behind) so the player can walk; but
        # BUDGET the sub-floor refinement, and cut it to 0 past max_cells. Unbudgeted moves refined each new
        # band to the eps floor in one shot and retention kept all of it, so a walk grew the tree without bound
        # (max_cells gated only the stationary drain, not moves). Budgeted, the move's deferred refinement
        # drains through the gated path below, so the whole system respects the cell budget.
        var move_budget := refine_us if _mesher.get_octree_cell_count() < max_cells else 0
        _dispatch_grow(p, move_budget, false)
    elif (_eps_dirty or _refine_pending) and _mesher.get_octree_cell_count() < max_cells:
        # c1 (doc 20): a pure DRAIN (refine_pending, eps unchanged) reuses the persistent frontier — skip the
        # reconcile re-walk. An eps change rebuilds it (the floor moved, so the candidate set changed).
        # Memory budget: stop refining past max_cells — at LOG2=4 max-detail the cell arena would exhaust RAM
        # (296 bytes/cell). The world holds at the detail that fit; a move still evicts + refines. mmap is the
        # real ceiling-raiser (M2); this is the honest "max detail until RAM is full" hardware-limit behaviour.
        _dispatch_grow(p, refine_us, not _eps_dirty)


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


# A box of the given radius around the player, in WORLD LATTICE, clamped to the root.
func _window_at(p: Vector3, radius_m: float) -> Array:
    var r := int(ceil(radius_m / base_cell))              # radius in lattice units
    var c := Vector3i((p / base_cell).round())
    var lo := _root_origin_i
    var hi := _root_origin_i + Vector3i.ONE * ROOT_SIZE
    return [(c - Vector3i.ONE * r).clamp(lo, hi), (c + Vector3i.ONE * r).clamp(lo, hi)]


# Visible window (DRAWN). M (doc 20): the larger residency window below keeps more than this resident.
func _window(p: Vector3) -> Array:
    return _window_at(p, win_radius_m)


# Residency window (SAMPLED + KEPT, pre-baked) — extends retain_margin_m beyond the visible window so a
# backtrack or turn re-samples nothing. Clamps to the root, so near a root edge it shrinks toward visible.
func _retained_window(p: Vector3) -> Array:
    return _window_at(p, win_radius_m + retain_margin_m)


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
    _pending_edit = false                         # a full rebuild already incorporates any pending edit
    _last_center = p
    var win := _window(p)
    _job_win_min = win[0]
    _job_win_max = win[1]
    _job_cam = _camera_lattice()
    _job_proj = _view_proj()
    _job_eps = _eps_px                            # capture the operating point for the worker
    _job_is_grow = false
    _job_is_edit = false
    _task_id = WorkerThreadPool.add_task(_run_job, false, "dcworld build")


# Incremental move: grow_world re-meshes only the band the move/eps change touched, reusing the retained
# octree (same root, no new store snapshot — grow reads the retained snapshot). The common path while walking.
func _dispatch_grow(p: Vector3, refine_budget: int, reuse: bool) -> void:
    _eps_dirty = false
    _last_center = p
    _job_reuse = reuse
    var ret := _retained_window(p)   # M: residency — sampled + kept
    var vis := _window(p)            # M: visible — drawn (emit filter)
    _job_win_min = ret[0]
    _job_win_max = ret[1]
    _job_emit_min = vis[0]
    _job_emit_max = vis[1]
    _job_cam = _camera_lattice()
    _job_proj = _view_proj()
    _job_eps = _eps_px
    _job_refine_budget = refine_budget
    _job_is_grow = true
    _job_is_edit = false
    _task_id = WorkerThreadPool.add_task(_run_job, false, "dcworld grow")


# Incremental edit (doc 20 E): re-mesh ONLY the edited box via edit_world, reusing the retained octree.
# Snapshot the store (it now includes the edit) so the worker samples it immutably, like the build path.
func _dispatch_edit(p: Vector3) -> void:
    _pending_edit = false
    _job_store = _edit_store.duplicate() if _edit_store != null else null
    _last_center = p
    _job_edit_min = _edit_min
    _job_edit_max = _edit_max
    _job_cam = _camera_lattice()
    _job_proj = _view_proj()
    _job_eps = _eps_px
    _job_is_grow = false
    _job_is_edit = true
    _task_id = WorkerThreadPool.add_task(_run_job, false, "dcworld edit")


func _run_job() -> void:
    var t0 := Time.get_ticks_usec()
    if _job_is_edit:
        _job_arrays = _mesher.edit_world(_job_store, _job_cam, _job_proj, _job_eps, _job_edit_min, _job_edit_max)
    elif _job_is_grow:
        _job_arrays = _mesher.grow_world(_job_cam, _job_proj, _job_eps, _job_win_min, _job_win_max, _job_refine_budget, _job_emit_min, _job_emit_max, _job_reuse)
    else:
        _job_arrays = _mesher.mesh_world(_job_store, _root_origin_i, DEPTH, base_cell,
                _job_cam, _job_proj, _job_eps, true, _palette, _job_win_min, _job_win_max, max_cells)
    # Tier-2: pack the ArrayMesh HERE on the worker, not in _finish on the main thread. The array→GPU-format
    # conversion is O(mesh) and was the ~1s main-thread stall at large meshes. RenderingServer is a
    # multithreaded command queue with no main-thread guard on mesh creation, so the pack runs off-thread and
    # the GPU upload command is marshalled safely; _finish then just assigns the finished mesh (a cheap swap).
    _job_mesh = _arrays_to_mesh(_job_arrays)
    _job_work_ms = (Time.get_ticks_usec() - t0) / 1000.0   # mesh lag = the controller's primary signal
    _refresh_mem_status()   # M2 telemetry computed HERE (worker owns _persist this job) — never on the main thread


# M2 readout: cells (O(1)) + arena bytes (O(1)) every job; the RAM-resident mincore scan (O(resident pages),
# a real hitch at hundreds of GB) only every Nth job. Runs on the worker at the end of _run_job — _persist is
# stable (this thread just built it) and the main thread never touches it, so there's no race and no stall.
func _refresh_mem_status() -> void:
    _ram_throttle += 1
    if _ram_throttle >= 10:
        _ram_throttle = 0
        _ram_gb = _mesher.get_cell_resident_bytes() / 1073741824.0
    var disk := _mesher.get_cell_arena_bytes() / 1073741824.0
    _mem_status = "%.1fM cells   RAM %.1f GB / arena %.1f GB" % [_mesher.get_octree_cell_count() / 1.0e6, _ram_gb, disk]


func _finish() -> void:
    WorkerThreadPool.wait_for_task_completion(_task_id)
    _task_id = -1
    if not _enabled:
        return
    var t0 := Time.get_ticks_usec()
    mesh = _job_mesh                  # tier-2: built on the worker — this is now a cheap RID swap, not a pack+upload
    _job_mesh = null
    # mesh_world verts are lattice-local to the root corner; place + scale back to world metres.
    global_position = Vector3(_root_origin_i) * base_cell
    scale = Vector3.ONE * base_cell
    visible = true
    Perf.report("dcworld swap (main)", (Time.get_ticks_usec() - t0) / 1000.0)
    Perf.mark_event()
    if _inval != null and _inval.is_enabled():
        _emit_diagnostic()   # refresh the dcinval LOD overlay for this mesh
    _refine_pending = _job_is_grow and _mesher.get_refine_pending()   # C: more refinement deferred → keep draining
    Perf.report_queue(_mesher.get_last_refine_queue_size() if _job_is_grow else 0)   # backlog graph in the perf window
    _check_arena_backing()   # M2: first build done → the cell arena has initialised; warn if it isn't disk-backed
    # Debug: when `dcverify` is on, the worker self-checks each emit for dangling-slot triangles. Toast ONCE on
    # the first trip (no per-frame spam); after that the full diagnostic streams over REST (/stats → "verify").
    if _mesher.get_last_bad_tri_count() > 0 and not _verify_tripped:
        _verify_tripped = true
        Toast.failure("DC emit verify TRIPPED (%s) — diagnostics now on REST /stats" % _job_kind())
    _control()


# M2: the cell arena initialises lazily on the first build. If it couldn't create a disk-backed temp file (no
# writable ./tmp or $DC_ARENA_DIR, or only tmpfs available) it falls back to anonymous RAM and the OOM-killer is
# back in play at high detail. That must never be a silent surprise, so pop a modal the moment we detect it.
func _check_arena_backing() -> void:
    if _arena_checked:
        return
    _arena_checked = true
    if _mesher.is_arena_disk_backed():
        return
    push_warning("DC cell arena fell back to anonymous RAM (no disk-backed temp file) — OOM risk at high detail.")
    if DisplayServer.get_name() == "headless":
        return
    var dlg := AcceptDialog.new()
    dlg.title = "⚠  Cell arena: no disk paging"
    dlg.dialog_text = ("The DC cell arena could not create a disk-backed temp file\n" +
            "(tried $DC_ARENA_DIR, ./tmp, /var/tmp) and fell back to RAM.\n\n" +
            "Cold cells can no longer page to disk, so the OOM-killer can\n" +
            "strike at high detail. Set DC_ARENA_DIR to a writable path on\n" +
            "a real (non-tmpfs) disk and relaunch.")
    dlg.process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().root.add_child(dlg)
    dlg.confirmed.connect(dlg.queue_free)
    dlg.canceled.connect(dlg.queue_free)
    dlg.popup_centered()


# Budget controller (doc 20): MAX DETAIL until the GPU complains. eps is the detail TARGET, driven toward the
# floor whenever the rendered frame has headroom — decoupled from the worker (NOT gated on _refine_pending). A
# CPU-bound worker used to freeze eps at the coarse start, so terrain never sharpened though the GPU sat idle;
# now eps heads to the floor and the worker chases it worst-on-screen-first at CPU speed, so the mesh sharpens
# progressively while the frame stays smooth. Only a real frame-budget overrun (too many triangles for the GPU)
# raises eps to coarsen — and raising eps sheds the cells with the SMALLEST projected error first (the far /
# flat ones, smallest on screen), so detail degrades least-visibly. Job work-ms never enters here: the worker
# is off the render thread, so its latency isn't frame cost. Damped: ×1.4 down-detail vs ×0.9 up-detail, with a
# 0.8–1.0 budget hysteresis band so eps settles instead of flapping. _eps_dirty re-meshes to apply a change.
func _control() -> void:
    var prev := _eps_px
    var over := _frame_ms > frame_budget
    # Don't drive finer than the memory budget can hold (the refine dispatch is gated on max_cells too).
    var under := _frame_ms < frame_budget * 0.8 and _mesher.get_octree_cell_count() < max_cells
    if over:
        _eps_px = minf(_eps_px * 1.4, EPS_MAX)
    elif under:
        _eps_px = maxf(_eps_px * 0.9, EPS_MIN)
    _eps_dirty = absf(_eps_px - prev) > 0.01


func set_frame_budget(ms: float) -> void:
    frame_budget = maxf(1.0, ms)
    _eps_dirty = true   # kick the controller to re-tune toward the new budget even while stationary


# Debug toggle (key I): incremental edits via edit_world vs. the default full-rebuild-on-edit. Returns the
# new state so the caller can surface it. OFF is the trusted path; ON is the doc-20-E work under inspection.
func toggle_incremental_edits() -> bool:
    incremental_edits = not incremental_edits
    return incremental_edits


# The kind of the last job, for the perf overlay (an incremental edit reads "edit", a move "grow").
func _job_kind() -> String:
    if _job_is_edit:
        return "edit"
    return "grow" if _job_is_grow else "build"


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
    return "threads %d | last grow: accel %.0f + build %.0f + collapse %.0f ms  [reset %.1f / collapse-walk %.1f / pass1 %.1f / pass2 %.1f]" % [
        _mesher.get_thread_count(),
        _mesher.get_last_accel_ms(),
        _mesher.get_last_build_ms(),
        _mesher.get_last_collapse_ms(),
        _mesher.get_last_reset_ms(),
        _mesher.get_last_collapse_pass_ms(),
        _mesher.get_last_pass1_ms(),
        _mesher.get_last_pass2_ms()]


func _exit_tree() -> void:
    if _task_id != -1:
        WorkerThreadPool.wait_for_task_completion(_task_id)
        _task_id = -1
