extends GutTest

# C++ port (SparseVoxelOctree) parity with the GDScript prototype: sub-metre sparse
# storage that reconstructs accurately and scales with surface area, not volume.

const CENTER := Vector3(8, 8, 8)
const RADIUS := 5.0
const ROOT := 16.0
const MIN_LEAF := 0.25


func _imprinted() -> SparseVoxelOctree:
    var t := SparseVoxelOctree.new()
    t.setup(Vector3.ZERO, ROOT)
    t.imprint_sphere(CENTER, RADIUS, MIN_LEAF, 3)
    return t


func test_reconstructs_surface_sub_metre() -> void:
    var t := _imprinted()
    var crossing := 0.0
    for i in range(1, 800):
        var x := i * 0.02
        if t.sample(CENTER + Vector3(x, 0, 0)) >= 0.0:
            crossing = x
            break
    gut.p("C++ reconstructed radius = %.3f (true %.1f)" % [crossing, RADIUS])
    assert_almost_eq(crossing, RADIUS, MIN_LEAF, "surface reconstructed to sub-metre")


func test_inside_solid_outside_air() -> void:
    var t := _imprinted()
    assert_lt(t.sample(CENTER), 0.0, "deep inside is solid")
    assert_gt(t.sample(Vector3(0.5, 0.5, 0.5)), 0.0, "far outside is air")


func test_material_round_trips() -> void:
    assert_eq(_imprinted().material_at(CENTER), 3)


func test_storage_is_sparse() -> void:
    var leaves := _imprinted().leaf_count()
    var dense := pow(ROOT / MIN_LEAF, 3)
    gut.p("C++ leaves=%d dense=%d ratio=%.4f" % [leaves, int(dense), leaves / dense])
    assert_lt(leaves, dense * 0.1, "stores the surface, not the volume")
    assert_gt(leaves, 0)


func test_box_imprint() -> void:
    var t := SparseVoxelOctree.new()
    t.setup(Vector3.ZERO, ROOT)
    t.imprint_box(Vector3(8, 8, 8), Vector3(4, 4, 4), MIN_LEAF, 1)   # faces at 6 and 10
    assert_lt(t.sample(Vector3(8, 8, 8)), 0.0, "box centre solid")
    assert_gt(t.sample(Vector3(8, 12, 8)), 0.0, "above the box is air")
