extends SceneTree

# E4: at the cell limit, how much of a carved cavity shows vs the unlimited edit, and how many cells the
# edit re-sampled. Calibrates test_edit_at_the_limit_resamples_coarse.

const T := preload("res://test/test_dc_cell_arena.gd")


func _init() -> void:
	var t = T.new()
	var s: EditStore = t._store()
	var o: Vector3i = t._region_origin(s)
	var free: DCOctreeMesher = t._build(s, o, T.WIN_FULL, T.FINE, 0)
	var limit := free.get_octree_cell_count()
	var m: DCOctreeMesher = t._build(s, o, T.WIN_FULL, T.FINE, limit)
	for cfg in [[14, 10.0], [10, 8.0], [8, 6.0], [12, 6.0], [6, 5.0]]:
		var y: int = cfg[0]
		var r: float = cfg[1]
		var local := Vector3(32, y, 32)
		var ctr := Vector3(o) + local
		var st: EditStore = s.duplicate()
		st.stamp_sphere(ctr, r, VoxelConstants.STORE_OP_SUBTRACT, 0, 1.0)
		var f: DCOctreeMesher = t._build(s, o, T.WIN_FULL, T.FINE, 0)
		var l: DCOctreeMesher = t._build(s, o, T.WIN_FULL, T.FINE, limit)
		var dmin := Vector3i((ctr - Vector3.ONE * 11.0).floor())
		var dmax := Vector3i((ctr + Vector3.ONE * 11.0).ceil())
		var want := f.edit_world(st, T.CAM, T.PROJ, T.FINE, dmin, dmax)
		var got := l.edit_world(st, T.CAM, T.PROJ, T.FINE, dmin, dmax)
		printerr("y=%d r=%s: want area=%.1f cells=%d samples=%d | limited area=%.1f cells=%d samples=%d hit=%s" % [y, r,
				t._area_near(want, local, r + 2.0), f.get_octree_cell_count(), f.get_last_build_sample_count(),
				t._area_near(got, local, r + 2.0), l.get_octree_cell_count(), l.get_last_build_sample_count(), l.get_cell_limit_hit()])
	quit()
