extends SceneTree

# Diag (Q8): bench_cell_arena's drain phase, per drain: slots added, refine time, reaccum, collapse+emit,
# pack/return overhead. Arg: radius (default 256), then drain budget us (default 20000).

const ROOT_ORIGIN := Vector3i(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0
const DEPTH       := 11
const PROJ        := 2000.0
const EPS         := 0.5
const EPS_COARSE  := 48.0
const DRAINS      := 30


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


func _init() -> void:
	var args   := OS.get_cmdline_user_args()
	var radius := int(args[0]) if args.size() > 0 else 256
	var budget := int(args[1]) if args.size() > 1 else 20000
	var s      := EditStore.new()
	s.setup(ROOT_ORIGIN, ROOT_SIZE, 30.0, 140.0, 1000.0, 2, 1337)

	var root   := 1 << DEPTH
	var surf   := int(round(_surface_y(s, 0.5, 0.5)))
	var origin := Vector3i(-root / 2, surf - root / 2, -root / 2)
	var c      := Vector3i(0, surf, 0)
	var wmin   := c - Vector3i(radius, radius, radius)
	var wmax   := c + Vector3i(radius, radius, radius)
	var cam    := Vector3(root / 2, root / 2 + 40, root / 2)

	var m := DCOctreeMesher.new()
	m.set_thread_count(mini(OS.get_processor_count(), 8))
	m.mesh_world(s, origin, DEPTH, 1.0, cam, PROJ, EPS_COARSE, true, PackedColorArray(), wmin, wmax)
	var t0 := Time.get_ticks_usec()
	m.grow_world(cam, PROJ, EPS, wmin, wmax, budget)
	var n0 := m.get_octree_cell_count()
	print("COLLECT cells=%d total=%.0f ms queue=%d" % [n0, (Time.get_ticks_usec() - t0) / 1000.0, m.get_last_refine_queue_size()])

	var sums := {"wall": 0.0, "refine": 0.0, "reaccum": 0.0, "collapse": 0.0, "pass1": 0.0, "pass2": 0.0, "rest": 0.0}
	var tris_last := 0
	var tall := Time.get_ticks_usec()
	for i in DRAINS:
		var before := m.get_octree_cell_count()
		t0 = Time.get_ticks_usec()
		var out := m.grow_world(cam, PROJ, EPS, wmin, wmax, budget, Vector3i.ZERO, Vector3i.ZERO, true)
		var wall := (Time.get_ticks_usec() - t0) / 1000.0
		var build := m.get_last_build_ms()
		var reacc := m.get_last_reaccum_ms()
		var refine := build - reacc - m.get_last_reconcile_ms()
		var coll := m.get_last_collapse_ms()
		var rest := wall - build - coll
		var added := m.get_octree_cell_count() - before
		tris_last = (out[0] as PackedVector3Array).size() if out.size() > 0 and out[0] is PackedVector3Array else -1
		sums.wall += wall; sums.refine += refine; sums.reaccum += reacc; sums.collapse += coll
		sums.pass1 += m.get_last_pass1_ms(); sums.pass2 += m.get_last_pass2_ms(); sums.rest += rest
		print("D%02d +%6d slots  wall=%6.1f refine=%5.1f (%.2f us/slot) reaccum=%5.1f collapse=%5.1f p1=%5.1f p2=%5.1f rest=%5.1f verts=%d" % [
				i, added, wall, refine, refine * 1000.0 / maxf(added, 1), reacc, coll,
				m.get_last_pass1_ms(), m.get_last_pass2_ms(), rest, tris_last])

	var total := (Time.get_ticks_usec() - tall) / 1000.0
	var added_all := m.get_octree_cell_count() - n0
	print("DRAIN x%d: cells=%d added=%d total=%.0f ms  queue=%d" % [DRAINS, m.get_octree_cell_count(), added_all, total, m.get_last_refine_queue_size()])
	print("SUMS refine=%.0f reaccum=%.0f collapse=%.0f (p1=%.0f p2=%.0f) rest=%.0f | refine us/slot=%.3f  total us/slot=%.3f  total us/cell=%.3f" % [
			sums.refine, sums.reaccum, sums.collapse, sums.pass1, sums.pass2, sums.rest,
			sums.refine * 1000.0 / added_all, total * 1000.0 / added_all, total * 1000.0 / m.get_octree_cell_count()])
	quit()
