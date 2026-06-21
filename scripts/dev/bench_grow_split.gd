extends SceneTree

# c4 diagnosis: where does a MOVE-grow's O(tree) build_ms actually go — reconcile (the graft/evict/collect
# walk) or reaccumulate (the QEF re-sum)? Build a large retained world octree, then do a few move-grows and
# print the split. The ratio is per-cell work, so it's scale-invariant; a ~1M-cell tree is representative.

const ROOT_ORIGIN := Vector3i(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0
const BASE := 30.0
const AMP := 140.0
const PERIOD := 1000.0
const OCTAVES := 2
const SEED := 1337

const DEPTH := 11          # root 2048 lattice — room for a deep surface octree
const PROJ  := 2000.0      # fine floor near the camera
const EPS   := 0.5


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
	var s := EditStore.new()
	s.setup(ROOT_ORIGIN, ROOT_SIZE, BASE, AMP, PERIOD, OCTAVES, SEED)
	var root := 1 << DEPTH
	var surf := int(round(_surface_y(s, 0.5, 0.5)))
	# Root corner: centre the lattice on the surface near world origin.
	var origin := Vector3i(-root / 2, surf - root / 2, -root / 2)
	var m := DCOctreeMesher.new()
	m.set_thread_count(mini(OS.get_processor_count(), 8))

	# A window around the surface centre (in WORLD lattice). Keep it a slab so the build stays ~1-3M cells.
	var c := Vector3i(0, surf, 0)
	var r := 384
	var wmin := c - Vector3i(r, r, r)
	var wmax := c + Vector3i(r, r, r)
	var cam := Vector3(root / 2, root / 2 + 40, root / 2)   # lattice-local, just above the surface centre

	var t0 := Time.get_ticks_usec()
	m.mesh_world(s, origin, DEPTH, 1.0, cam, PROJ, EPS, true, PackedColorArray(), wmin, wmax)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("BUILD: cells=%d  build=%.0f ms" % [m.get_octree_cell_count(), build_ms])

	# A few MOVES: shift the camera + window by a step each grow (unbudgeted = full coverage, like a real move).
	for i in range(1, 5):
		var step := Vector3i(24 * i, 0, 0)
		var gmin := wmin + step
		var gmax := wmax + step
		var gcam := cam + Vector3(24 * i, 0, 0)
		m.grow_world(gcam, PROJ, EPS, gmin, gmax, -1)
		print("MOVE %d: cells=%d  reconcile=%.0f  reaccum=%.0f  collapse=%.0f  [reset=%.0f  collapse_walk=%.0f  pass1=%.0f  pass2=%.0f]" % [
				i, m.get_octree_cell_count(),
				m.get_last_reconcile_ms(), m.get_last_reaccum_ms(), m.get_last_collapse_ms(),
				m.get_last_reset_ms(), m.get_last_collapse_pass_ms(), m.get_last_pass1_ms(), m.get_last_pass2_ms()])
	quit()
