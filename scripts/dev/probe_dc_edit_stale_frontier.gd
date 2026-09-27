extends SceneTree

# Throwaway (E3, doc 20 "Frontier lazy invalidation"): budgeted grow -> edit_world -> reuse
# drain. Does the drained tree match (a) the same edit applied after an UNBUDGETED grow, (b) a fresh build of
# the edited store? Does the cell arena leak (orphaned subtrees) vs the reference?

const T := preload("res://test/test_dc_world_octree.gd")
const COARSE := 32.0
const FINE   := 2.0


func _init() -> void:
	var t: GutTest = T.new()
	var cases := [
		["sphere-sub r3", "sphere", 1, 3.0],
		["box-union 12", "box", 0, 12.0],
		["box-sub 12", "box", 1, 12.0],
		["box-union 20", "box", 0, 20.0],
	]
	for c in cases:
		for whole in [false, true]:
			_run(t, c, whole)
	t.free()
	quit()


func _edit(s: EditStore, ctr: Vector3, c: Array) -> void:
	if c[1] == "sphere":
		s.stamp_sphere(ctr, c[3], c[2], 0, 1.0)
	else:
		s.stamp_box(ctr, Vector3.ONE * c[3], c[2], 0, 1.0)


func _run(t: GutTest, c: Array, whole: bool) -> void:
	var s: EditStore = t._store()
	var origin: Vector3i = t._region_origin(s)
	var cam := Vector3(16, 16, 120)
	var lo := origin
	var hi := origin + Vector3i(32, 32, 32)
	var ctr := Vector3(origin.x + 16, origin.y + 16, origin.z + 16)
	var half: float = c[3] * 0.5 + 1.0 if c[1] == "box" else c[3] + 1.0
	var dmin := Vector3i((ctr - Vector3.ONE * half).floor())
	var dmax := Vector3i((ctr + Vector3.ONE * half).ceil())
	if whole:
		dmin = lo
		dmax = hi

	var ref_store: EditStore = t._store()
	var rm := DCOctreeMesher.new()
	rm.mesh_world(ref_store, origin, 5, 1.0, cam, 500.0, COARSE, true, PackedColorArray(), lo, hi)
	rm.grow_world(cam, 500.0, FINE, lo, hi)
	_edit(ref_store, ctr, c)
	rm.edit_world(ref_store, cam, 500.0, FINE, dmin, dmax)
	var ref_sigs: PackedStringArray = t._tri_sigs(rm.remesh(cam, 500.0, FINE))

	var bm := DCOctreeMesher.new()
	bm.mesh_world(s, origin, 5, 1.0, cam, 500.0, COARSE, true, PackedColorArray(), lo, hi)
	bm.grow_world(cam, 500.0, FINE, lo, hi, 0, Vector3i(), Vector3i(), false)
	var queue := bm.get_last_refine_queue_size()
	_edit(s, ctr, c)
	bm.edit_world(s, cam, 500.0, FINE, dmin, dmax)
	var n := 0
	var retired := 0
	var out: Array = []
	while bm.get_refine_pending() and n < 20000:
		out = bm.grow_world(cam, 500.0, FINE, lo, hi, 100, Vector3i(), Vector3i(), true)
		n += 1
		retired += bm.get_last_refine_retired_count()
	var drained_sigs: PackedStringArray = t._tri_sigs(out) if not out.is_empty() else PackedStringArray()
	var got: PackedStringArray = t._tri_sigs(bm.remesh(cam, 500.0, FINE))

	var fm := DCOctreeMesher.new()
	var fresh: PackedStringArray = t._tri_sigs(fm.mesh_world(s, origin, 5, 1.0, cam, 500.0, FINE, true, PackedColorArray(), lo, hi))
	print("retired=%d drained==fresh:%s" % [retired, drained_sigs == fresh])
	print("%-14s whole=%-5s queue=%d drains=%d  ==ref:%s  ==fresh:%s  ref==fresh:%s  cells b=%d r=%d  tris b=%d r=%d f=%d" % [
			c[0], whole, queue, n, got == ref_sigs, got == fresh, ref_sigs == fresh,
			bm.get_octree_cell_count(), rm.get_octree_cell_count(), got.size(), ref_sigs.size(), fresh.size()])
