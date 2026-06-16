extends GutTest

# TerrainField (C++): the procedural terrain as a fine analytic SDF field.
# FIDELITY — its surface matches the params below (the single terrain definition).

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
        var ours   := EditStore.terrain_surface(p.x, p.y, BASE, AMP, PERIOD, OCTAVES, SEED)
        var theirs := _graph_surface(p.x, p.y)
        assert_almost_eq(ours, theirs, 0.01, "C++ field surface matches ZN noise at %s" % p)
