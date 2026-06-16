extends GutTest

# TerrainRaymarch: sub-metre aim via SDF sphere-trace. Must land ON the surface (not 1m-quantized
# like a physics raycast against the coarse collision mesh), report an outward normal, and miss
# cleanly when the ray sees only air.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

func _store() -> EditStore:
    var es := EditStore.new()
    es.setup(Vector3(-256, -256, -256), 512.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return es


func test_marches_down_to_the_terrain_surface() -> void:
    var es := _store()
    var s0 := EditStore.terrain_surface(0, 0, BASE, AMP, PERIOD, OCTAVES, SEED)
    # Straight down from well above the surface.
    var origin := Vector3(0, s0 + 20.0, 0)
    var hit := TerrainRaymarch.surface(es, origin, Vector3.DOWN, 40.0, 0.2)
    assert_true(hit.hit, "the downward ray hit the terrain")
    assert_almost_eq(hit.position.y, s0, 0.3, "hit lands on the surface, sub-metre accurate (not 1m-quantized)")
    assert_almost_eq(hit.position.x, 0.0, 0.01, "hit stays on the ray (x)")
    assert_gt(hit.normal.y, 0.3, "surface normal points generally up/outward")


func test_offset_edit_is_hit_at_its_true_position() -> void:
    # A solid box stamped at a sub-metre-offset height; aiming down must hit its TOP face at that
    # offset position, not snapped to a 1m grid.
    var es := _store()
    var s0 := EditStore.terrain_surface(0, 0, BASE, AMP, PERIOD, OCTAVES, SEED)
    var top := s0 + 30.0
    es.stamp_box(Vector3(0, top - 1.0, 0), Vector3(4, 2, 4), VoxelConstants.STORE_OP_UNION,
        MaterialPalette.index_of(&"Wood"), VoxelConstants.RENDER_BASE_CELL)
    var box_top := top   # box spans [top-2, top]
    var hit := TerrainRaymarch.surface(es, Vector3(0, top + 10.0, 0), Vector3.DOWN, 20.0, 0.2)
    assert_true(hit.hit, "hit the stamped box")
    assert_almost_eq(hit.position.y, box_top, 0.3, "hit lands on the box's true top, not a 1m-snapped height")


func test_air_ray_misses() -> void:
    var es := _store()
    var s0 := EditStore.terrain_surface(0, 0, BASE, AMP, PERIOD, OCTAVES, SEED)
    # Aim straight up from above the surface — only air ahead.
    var hit := TerrainRaymarch.surface(es, Vector3(0, s0 + 10.0, 0), Vector3.UP, 30.0, 0.2)
    assert_false(hit.hit, "a ray into open air reports no hit")
