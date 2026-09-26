extends SceneTree

# Throwaway probe for the (now fixed, file deleted) dc-mesher-latent-arg-traps bug: prints what each trap does on the
# current build, so the old and new behaviour can be compared side by side.
# Run: bin/godot --path . --headless -s scripts/dev/probe_dc_arg_traps.gd

const ROOT_ORIGIN := Vector3(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0
const SIZE  := 32
const DIM   := SIZE + 1
const DEPTH := 5
const CAM   := Vector3(16, 16, 120)


func _store() -> EditStore:
	var s := EditStore.new()
	s.setup(ROOT_ORIGIN, ROOT_SIZE, 30.0, 140.0, 1000.0, 2, 1337)
	return s


func _tri_count(arrays: Array) -> int:
	return 0 if arrays.is_empty() else (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


func _init() -> void:
	var s := _store()
	var origin := Vector3i(-16, int(round(_surface_y(s))) - 16, -16)
	var grid := s.fill_region(origin, DIM, 1.0, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO)
	var m := DCOctreeMesher.new()
	var full := m.mesh_clipmap([grid], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
			Vector3(16, 16, 16), 1e9, DEPTH, CAM, 500.0, 2.0, true)
	print("trap1 full build tris=%d  remesh(far cam) tris=%d" % [_tri_count(full), _tri_count(m.remesh(Vector3(16, 16, 5000), 500.0, 2.0))])
	var box := Vector3i(5, 5, 5)
	if m.has_method("mesh_clipmap_splice"):
		print("trap1 new API present; see GUT")
	else:
		var degen: Array = m.call("mesh_clipmap", [grid], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
				Vector3(16, 16, 16), 1e9, DEPTH, Vector3(16, 16, 5000), 500.0, 2.0, true, Vector3i.ZERO,
				[], PackedColorArray(), false, 0.0, box, box, box, box)
		print("trap1 degenerate (5,5,5) box: tris=%d (== an unboxed build at the far cam if the box was ignored)" % _tri_count(degen))

	var lo := Vector3i(-16, int(round(_surface_y(s))) - 16, -16)
	var hi := lo + Vector3i(SIZE, SIZE, SIZE)
	var ref := DCOctreeMesher.new()
	ref.mesh_world(s, lo, DEPTH, 1.0, CAM, 500.0, 32.0, true, PackedColorArray(), lo, hi)
	var full_grow := ref.grow_world(CAM, 500.0, 2.0, lo, hi)
	var b := DCOctreeMesher.new()
	b.mesh_world(s, lo, DEPTH, 1.0, CAM, 500.0, 32.0, true, PackedColorArray(), lo, hi)
	b.grow_world(CAM, 500.0, 2.0, lo, hi, 0, Vector3i(), Vector3i(), false)
	print("trap2 after budget-0 rebuild: pending=%s queue=%d" % [b.get_refine_pending(), b.get_last_refine_queue_size()])
	var drained := b.grow_world(CAM, 500.0, 2.0, lo, hi, -1, Vector3i(), Vector3i(), true)
	print("trap2 reuse+(-1): pending=%s queue=%d tris=%d (unbudgeted reference tris=%d)" % [
			b.get_refine_pending(), b.get_last_refine_queue_size(), _tri_count(drained), _tri_count(full_grow)])
	var c := DCOctreeMesher.new()
	c.mesh_world(s, lo, DEPTH, 1.0, CAM, 500.0, 32.0, true, PackedColorArray(), lo, hi)
	c.grow_world(CAM, 500.0, 2.0, lo, hi, 0, Vector3i(), Vector3i(), false)
	c.grow_world(CAM, 500.0, 2.0, lo, hi, -1, Vector3i(), Vector3i(), false)
	print("trap2b unbudgeted rebuild after a budgeted one: pending=%s queue=%d" % [c.get_refine_pending(), c.get_last_refine_queue_size()])
	quit()


func _surface_y(s: EditStore) -> float:
	var lo := -400.0
	var hi := 400.0
	for _i in 48:
		var mid := (lo + hi) * 0.5
		if s.sample(Vector3(0.5, mid, 0.5)) < 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5
