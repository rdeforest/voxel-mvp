extends SceneTree

# E3 (doc 20 "Frontier lazy invalidation"): time budgeted reuse drains on a large retained tree, before vs
# after the generation check, with and without an edit in between. Prints per-phase medians.

const ROOT_ORIGIN := Vector3i(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0
const DEPTH  := 9
const PROJ   := 500.0
const COARSE := 32.0
const FINE   := 2.0
const BUDGET := 4000
const DRAINS := 40


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


func _median(xs: Array) -> float:
	var ys := xs.duplicate()
	ys.sort()
	return ys[ys.size() / 2]


func _init() -> void:
	var s := EditStore.new()
	s.setup(ROOT_ORIGIN, ROOT_SIZE, 30.0, 140.0, 1000.0, 2, 1337)
	var root := 1 << DEPTH
	var surf := int(round(_surface_y(s, 0.5, 0.5)))
	var origin := Vector3i(-root / 2, surf - root / 2, -root / 2)
	var c := Vector3i(0, surf, 0)
	var wmin := c - Vector3i(192, 192, 192)
	var wmax := c + Vector3i(192, 192, 192)
	var cam := Vector3(root / 2, root / 2 + 40, root / 2)

	for edit in [false, true]:
		var m := DCOctreeMesher.new()
		m.set_thread_count(mini(OS.get_processor_count(), 8))
		m.mesh_world(s, origin, DEPTH, 1.0, cam, PROJ, COARSE, true, PackedColorArray(), wmin, wmax)
		var t0 := Time.get_ticks_usec()
		m.grow_world(cam, PROJ, FINE, wmin, wmax, BUDGET, Vector3i(), Vector3i(), false)
		var rebuild_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var queued := m.get_last_refine_queue_size()
		if edit:
			var ctr := Vector3(0, surf, 0)
			s.stamp_sphere(ctr, 12.0, 1, 0, 1.0)
			m.edit_world(s, cam, PROJ, FINE, Vector3i(ctr) - Vector3i(14, 14, 14), Vector3i(ctr) + Vector3i(14, 14, 14))
		_drain(m, cam, wmin, wmax, "edit=%s rebuild=%.1f ms queued=%d" % [edit, rebuild_ms, queued])
	quit()


func _drain(m: DCOctreeMesher, cam: Vector3, wmin: Vector3i, wmax: Vector3i, head: String) -> void:
	var totals := []
	var builds := []
	var collapses := []
	var retired := 0
	for _i in DRAINS:
		var t0 := Time.get_ticks_usec()
		m.grow_world(cam, PROJ, FINE, wmin, wmax, BUDGET, Vector3i(), Vector3i(), true)
		totals.append((Time.get_ticks_usec() - t0) / 1000.0)
		builds.append(m.get_last_build_ms())
		collapses.append(m.get_last_collapse_ms())
		if m.has_method("get_last_refine_retired_count"):
			retired += m.call("get_last_refine_retired_count")

	print("%s | drain median total=%.2f build=%.2f collapse=%.2f ms | left=%d retired=%d cells=%d" % [
			head, _median(totals), _median(builds), _median(collapses),
			m.get_last_refine_queue_size(), retired, m.get_octree_cell_count()])
