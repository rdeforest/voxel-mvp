extends SceneTree

# Cell-arena timing + peak RSS. Phase 1: one mesh_world build at the data floor and a few unbudgeted
# move-grows (bench_grow_split's world). Phase 2: a coarse build at the game's starting eps, a budgeted grow
# at the finest eps that collects the frontier, and reuse grows that drain it (the refine_selected path).
# Window half-size is the first user arg (default 256, well under the cell cap; 384 reaches the cap). Peak
# RSS is read from /proc (Linux only).
#   bin/godot --path . --headless -s scripts/dev/bench_cell_arena.gd -- 256

const ROOT_ORIGIN := Vector3i(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0
const BASE        := 30.0
const AMP         := 140.0
const PERIOD      := 1000.0
const OCTAVES     := 2
const SEED        := 1337
const DEPTH       := 11
const PROJ        := 2000.0
const EPS         := 0.5
const EPS_COARSE  := 48.0
const MOVES       := 4
const DRAINS      := 30
const DRAIN_US    := 20000


func _surface_y(s: EditStore, x: float, z: float) -> float:
	var lo := -400.0
	var hi := 400.0
	for _i in 48:
		var mid := (lo + hi) * 0.5
		if s.sample(Vector3(x, mid, z)) < 0.0:
			lo = mid
		else:
			hi = mid

	return (lo + hi) * 0.5


func _peak_rss_mb() -> int:
	var out := []
	OS.execute("grep", ["VmHWM", "/proc/%d/status" % OS.get_process_id()], out)
	if out.is_empty() or not String(out[0]).begins_with("VmHWM:"):
		return -1

	return int(String(out[0]).split(":")[1].strip_edges().split(" ")[0]) / 1024


func _init() -> void:
	var args   := OS.get_cmdline_user_args()
	var radius := int(args[0]) if args.size() > 0 else 256
	var s      := EditStore.new()
	s.setup(ROOT_ORIGIN, ROOT_SIZE, BASE, AMP, PERIOD, OCTAVES, SEED)

	var root := 1 << DEPTH
	var surf := int(round(_surface_y(s, 0.5, 0.5)))
	var origin := Vector3i(-root / 2, surf - root / 2, -root / 2)
	var c      := Vector3i(0, surf, 0)
	var wmin   := c - Vector3i(radius, radius, radius)
	var wmax   := c + Vector3i(radius, radius, radius)
	var cam    := Vector3(root / 2, root / 2 + 40, root / 2)

	_moves(s, origin, cam, wmin, wmax)
	_drains(s, origin, cam, wmin, wmax)
	print("PEAK_RSS_MB %d" % _peak_rss_mb())
	quit()


func _mesher() -> DCOctreeMesher:
	var m := DCOctreeMesher.new()
	m.set_thread_count(mini(OS.get_processor_count(), 8))
	return m


func _moves(s: EditStore, origin: Vector3i, cam: Vector3, wmin: Vector3i, wmax: Vector3i) -> void:
	var m  := _mesher()
	var t0 := Time.get_ticks_usec()
	m.mesh_world(s, origin, DEPTH, 1.0, cam, PROJ, EPS, true, PackedColorArray(), wmin, wmax)
	print("BUILD: cells=%d  build=%.0f ms" % [m.get_octree_cell_count(), (Time.get_ticks_usec() - t0) / 1000.0])

	for i in range(1, MOVES + 1):
		var step := Vector3i(24 * i, 0, 0)
		t0 = Time.get_ticks_usec()
		m.grow_world(cam + Vector3(step), PROJ, EPS, wmin + step, wmax + step, -1)
		print("MOVE %d: cells=%d  total=%.0f  reconcile=%.0f  reaccum=%.0f  collapse=%.0f" % [
				i, m.get_octree_cell_count(), (Time.get_ticks_usec() - t0) / 1000.0,
				m.get_last_reconcile_ms(), m.get_last_reaccum_ms(), m.get_last_collapse_ms()])

	print("MOVES_RSS_MB %d  ARENA_MB %d" % [_peak_rss_mb(), m.get_cell_arena_bytes() / 1048576])


func _drains(s: EditStore, origin: Vector3i, cam: Vector3, wmin: Vector3i, wmax: Vector3i) -> void:
	var m  := _mesher()
	m.mesh_world(s, origin, DEPTH, 1.0, cam, PROJ, EPS_COARSE, true, PackedColorArray(), wmin, wmax)
	var t0 := Time.get_ticks_usec()
	m.grow_world(cam, PROJ, EPS, wmin, wmax, DRAIN_US)
	print("COLLECT: cells=%d  total=%.0f ms  queue=%d" % [
			m.get_octree_cell_count(), (Time.get_ticks_usec() - t0) / 1000.0, m.get_last_refine_queue_size()])

	t0 = Time.get_ticks_usec()
	for _i in DRAINS:
		m.grow_world(cam, PROJ, EPS, wmin, wmax, DRAIN_US, Vector3i.ZERO, Vector3i.ZERO, true)

	print("DRAIN x%d: cells=%d  total=%.0f ms  queue=%d" % [DRAINS, m.get_octree_cell_count(),
			(Time.get_ticks_usec() - t0) / 1000.0, m.get_last_refine_queue_size()])
