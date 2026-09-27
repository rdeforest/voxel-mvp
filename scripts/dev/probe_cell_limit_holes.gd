extends SceneTree

# E4: calibrates COVERED in test_dc_cell_arena — the XZ-projected surface area a limited build/move/drain
# keeps, as a fraction of its unlimited counterpart's. A hole (absent cells) measures 0 for its region.

const T := preload("res://test/test_dc_cell_arena.gd")


func _init() -> void:
	var t = T.new()
	var s: EditStore = t._store()
	var o: Vector3i = t._region_origin(s)
	var full := T.WIN_FULL

	var free: Array = t._build(s, o, full, T.COARSE, 0).remesh(T.CAM, T.PROJ, T.COARSE)
	var capped: Array = t._build(s, o, full, T.FINE, 200).remesh(T.CAM, T.PROJ, T.FINE)
	printerr("build: %.2f" % [t._xz_area(capped, 0.0) / t._xz_area(free, 0.0)])

	for budget in [-1, 0]:
		var near: DCOctreeMesher = t._build(s, o, T.WIN_NEAR, T.COARSE, 0)
		var limit := near.get_octree_cell_count()
		var want: Array = near.grow_world(T.CAM, T.PROJ, T.COARSE, o, o + full)
		var got: Array = t._build(s, o, T.WIN_NEAR, T.COARSE, limit).grow_world(T.CAM, T.PROJ, T.COARSE, o, o + full, budget)
		var hole: Array = t._build(s, o, T.WIN_NEAR, T.COARSE, 0).remesh(T.CAM, T.PROJ, T.COARSE)
		printerr("move budget %d: %.2f (window left un-grafted: %.2f)" % [budget,
				t._xz_area(got, T.GRAFT_X) / t._xz_area(want, T.GRAFT_X), t._xz_area(hole, T.GRAFT_X) / t._xz_area(want, T.GRAFT_X)])
	quit()
