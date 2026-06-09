extends GutTest

# TerrainField (C++): the procedural terrain as a fine analytic SDF field — the
# store-over-generator baseline for the octree substrate (fine everywhere, no
# godot_voxel mips). Two things must hold:
#   1. FIDELITY — its surface matches the SAME ZN_FastNoiseLite the .tres graph's
#      FastNoise2D node uses (so octree-meshed terrain agrees with godot_voxel-
#      streamed terrain while the two coexist). These params mirror
#      tools/build_terrain_graph.gd.
#   2. RECONSTRUCTION — imprinting it into the sparse octree reproduces that surface
#      (the adaptive store captures a heightfield, not just analytic blobs).

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337


# The graph's FastNoise2D node wraps a ZN_FastNoiseLite with exactly this config, so
# this reproduces the live generator's surface without needing the graph itself.
func _graph_surface(x: float, z: float) -> float:
    var n := ZN_FastNoiseLite.new()
    n.noise_type      = ZN_FastNoiseLite.TYPE_OPEN_SIMPLEX_2
    n.fractal_type    = ZN_FastNoiseLite.FRACTAL_RIDGED
    n.seed            = SEED
    n.period          = PERIOD
    n.fractal_octaves = OCTAVES
    return BASE + AMP * n.get_noise_2d(x, z)


func test_field_matches_graph_noise() -> void:
    for p in [Vector2(0, 0), Vector2(37, 11), Vector2(-120, 240), Vector2(512, -333)]:
        var ours   := SparseVoxelOctree.terrain_surface(p.x, p.y, BASE, AMP, PERIOD, OCTAVES, SEED)
        var theirs := _graph_surface(p.x, p.y)
        assert_almost_eq(ours, theirs, 0.01, "C++ field surface matches ZN noise at %s" % p)


func test_octree_reconstructs_surface() -> void:
    # Ridged noise is locally steep, so use a 64 m cube and only check columns whose
    # surface sits well inside it (a column exiting a cube face can't be resolved).
    # Tolerance is a couple of leaves: the terrain SDF (y - surface) is not a true
    # unit-distance field, so DC reconstruction softens on slopes ([[dc-sdf-not-unit-distance]]).
    var s0 := SparseVoxelOctree.terrain_surface(32, 32, BASE, AMP, PERIOD, OCTAVES, SEED)
    var t := SparseVoxelOctree.new()
    t.setup(Vector3(0, s0 - 32, 0), 64.0)
    t.imprint_terrain(BASE, AMP, PERIOD, OCTAVES, SEED, 0.5)
    assert_gt(t.leaf_count(), 0, "imprinted leaves")
    var checked := 0
    for xz in [Vector2(32, 32), Vector2(28, 36), Vector2(36, 30), Vector2(30, 28)]:
        var want := SparseVoxelOctree.terrain_surface(xz.x, xz.y, BASE, AMP, PERIOD, OCTAVES, SEED)
        if want <= s0 - 24 or want >= s0 + 24:
            continue   # column exits a cube face — not a fair reconstruction test
        var crossing := _octree_crossing(t, xz.x, xz.y, s0 - 32, s0 + 32)
        assert_almost_eq(crossing, want, 1.5, "octree surface at %s" % xz)
        checked += 1
    assert_gt(checked, 0, "at least one column was well-bracketed")


func test_graded_terrain_fine_near_focus_and_sparser_than_uniform() -> void:
    # The live render path: one octree spanning the view, fine near the camera focus.
    var s0 := SparseVoxelOctree.terrain_surface(32, 32, BASE, AMP, PERIOD, OCTAVES, SEED)
    var focus := Vector3(32, s0, 32)
    var graded := SparseVoxelOctree.new()
    graded.setup(Vector3(0, s0 - 32, 0), 64.0)
    graded.imprint_terrain_graded(focus, 0.5, 16.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    # Reconstructs the surface near the focus (where it's fine) — the magnitude-prune bug
    # would leave a coarse leaf here and throw this off by several metres.
    var want := SparseVoxelOctree.terrain_surface(32, 32, BASE, AMP, PERIOD, OCTAVES, SEED)
    if want > s0 - 24 and want < s0 + 24:
        assert_almost_eq(_octree_crossing(graded, 32, 32, s0 - 32, s0 + 32), want, 1.5, "fine near focus")
    # Grading coarsens far cells, so it stores fewer leaves than a uniform fine imprint.
    var uniform := SparseVoxelOctree.new()
    uniform.setup(Vector3(0, s0 - 32, 0), 64.0)
    uniform.imprint_terrain(BASE, AMP, PERIOD, OCTAVES, SEED, 0.5)
    assert_lt(graded.leaf_count(), uniform.leaf_count(), "grading is sparser than uniform-fine")


# March up the column; SDF crosses negative (solid, below ground) -> positive (air).
func _octree_crossing(t: SparseVoxelOctree, x: float, z: float, y_lo: float, y_hi: float) -> float:
    var y := y_lo
    while y <= y_hi:
        if t.sample(Vector3(x, y, z)) >= 0.0:
            return y
        y += 0.1
    return y_hi
