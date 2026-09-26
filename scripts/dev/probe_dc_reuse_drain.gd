extends SceneTree

# Throwaway: does a reuse drain's rendered surface match the unbudgeted grow, by first-grow budget and drain
# budget? With the drop catcher on, the returned arrays are its full re-emit and dropped_total counts what the
# incremental emit lost (docs/bugs/dc-incremental-emit-ring-insufficient.md).

const T := preload("res://test/test_dc_world_octree.gd")


func _init() -> void:
	var t: GutTest = T.new()
	var s: EditStore = t._store()
	var origin: Vector3i = t._region_origin(s)
	var cam := Vector3(16, 16, 120)
	var lo := origin
	var hi := origin + Vector3i(32, 32, 32)
	var rm := DCOctreeMesher.new()
	rm.mesh_world(s, origin, 5, 1.0, cam, 500.0, 32.0, true, PackedColorArray(), lo, hi)
	var full_sigs: PackedStringArray = t._tri_sigs(rm.grow_world(cam, 500.0, 2.0, lo, hi))
	for catcher in [false, true]:
		for first in [0, 100]:
			for drain in [-1, 1000000000, 100]:
				_run(t, s, origin, full_sigs, catcher, first, drain)
	t.free()
	quit()


func _run(t: GutTest, s: EditStore, origin: Vector3i, full_sigs: PackedStringArray, catcher: bool, first: int, drain: int) -> void:
	var cam := Vector3(16, 16, 120)
	var lo := origin
	var hi := origin + Vector3i(32, 32, 32)
	var m := DCOctreeMesher.new()
	m.set_emit_diff(catcher)
	m.mesh_world(s, origin, 5, 1.0, cam, 500.0, 32.0, true, PackedColorArray(), lo, hi)
	var out: Array = m.grow_world(cam, 500.0, 2.0, lo, hi, first, Vector3i(), Vector3i(), false)
	var n := 0
	while m.get_refine_pending() and n < 20000:
		out = m.grow_world(cam, 500.0, 2.0, lo, hi, drain, Vector3i(), Vector3i(), true)
		n += 1
	var sigs: PackedStringArray = t._tri_sigs(out)
	print("catcher=%s first=%d drain=%d grows=%d match=%s (%d vs %d sigs) dropped_total=%d" % [catcher, first, drain, n, sigs == full_sigs, sigs.size(), full_sigs.size(), m.get_emit_diff_total_drop()])
