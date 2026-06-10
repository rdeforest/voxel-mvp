extends GutTest

# EditStore: the persistent sparse store that holds ONLY edits and defers to the
# TerrainField generator everywhere else. Pins the copy-on-write behaviour (first edit
# materialises from the generator; re-edits combine with the STORED value, not the
# generator), the defer-to-generator sampling, and serialize round-trip.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337
const UNION    := 0
const SUBTRACT := 1

const CX := 100.0
const CZ := 100.0


func _store() -> EditStore:
    var s0 := SparseVoxelOctree.terrain_surface(CX, CZ, BASE, AMP, PERIOD, OCTAVES, SEED)
    var es := EditStore.new()
    es.setup(Vector3(CX - 128.0, s0 - 128.0, CZ - 128.0), 256.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return es

func _surface() -> float:
    return SparseVoxelOctree.terrain_surface(CX, CZ, BASE, AMP, PERIOD, OCTAVES, SEED)


func test_unedited_defers_to_generator() -> void:
    var es := _store()
    var s0 := _surface()
    assert_lt(es.sample(Vector3(CX, s0 - 10, CZ)), 0.0, "below surface reads solid (generator)")
    assert_gt(es.sample(Vector3(CX, s0 + 10, CZ)), 0.0, "above surface reads air (generator)")
    assert_false(es.has_edit(Vector3(CX, s0 - 10, CZ)), "nothing stored before any edit")
    assert_eq(es.leaf_count(), 0, "empty store has no stored leaves")


func test_carve_over_generator() -> void:
    var es := _store()
    var s0 := _surface()
    var center := Vector3(CX, s0 - 5.0, CZ)   # below the surface = solid generator
    es.stamp_sphere(center, 4.0, SUBTRACT, 0, 1.0)
    assert_gt(es.sample(center), 0.0, "carved cell is now air")
    assert_true(es.has_edit(center), "carved cell is stored")
    var far := Vector3(CX, s0 - 5.0, CZ + 30.0)
    assert_false(es.has_edit(far), "outside the brush stays unstored")
    assert_lt(es.sample(far), 0.0, "outside the brush still defers to the generator (solid)")


func test_fill_over_generator_paints_material() -> void:
    var es := _store()
    var s0 := _surface()
    var center := Vector3(CX, s0 + 8.0, CZ)   # above the surface = air generator
    es.stamp_sphere(center, 3.0, UNION, 5, 1.0)
    assert_lt(es.sample(center), 0.0, "filled cell is now solid")
    assert_true(es.has_edit(center), "filled cell is stored")
    assert_eq(es.material_at(center), 5, "fill paints its material")


func test_reedit_combines_with_stored_not_generator() -> void:
    var es := _store()
    var s0 := _surface()
    var p := Vector3(CX, s0 - 20.0, CZ)        # 20 m down: generator is ~ -20 here
    assert_lt(es.sample(p), -10.0, "precondition: generator is deep solid at p")
    es.stamp_sphere(p, 6.0, SUBTRACT, 0, 1.0)  # carve a big air pocket
    assert_gt(es.sample(p), 0.0, "carved to air")
    es.stamp_sphere(p, 2.0, UNION, 1, 1.0)     # fill a small ball back in
    # min(stored_air, -2) = -2 (stored base). If it combined with the GENERATOR it'd be
    # min(-20, -2) = -20 — so a value near -2, far from -20, proves stored-base.
    var v := es.sample(p)
    assert_lt(v, 0.0, "re-fill made it solid again")
    assert_gt(v, -6.0, "combined with the STORED air (~-2), not the generator (~-20)")


func test_write_region_stores_an_array() -> void:
    # The dual-write path: write a dense SDF array (a region re-read from godot_voxel) into
    # the store, replacing whatever was there; the rest defers to the generator.
    var es := _store()
    var s0 := _surface()
    var dim := 9
    var arr := PackedFloat32Array()
    arr.resize(dim * dim * dim)
    arr.fill(-5.0)                              # a solid block...
    var origin := Vector3(CX, s0 + 20.0, CZ)    # ...placed above the surface (generator = air)
    es.write_region(arr, PackedByteArray(), dim, origin, 1.0)
    assert_lt(es.sample(origin + Vector3.ONE * 4.0), 0.0, "written region reads the array's solid value")
    assert_true(es.has_edit(origin + Vector3.ONE * 4.0), "written region is stored")
    assert_gt(es.sample(Vector3(CX, s0 + 60.0, CZ)), 0.0, "outside the written region defers to the generator")


func test_imprint_store_graded_bakes_edits_into_render_octree() -> void:
    # S3 render path: a SparseVoxelOctree imprinted from the store carries generator + edits.
    # Use a SURFACE dig (the supported case — the octree is already subdivided at the
    # surface). A small floating edit in empty air is undersampled by the graded octree's
    # homogeneity prune; that's a separate limitation, noted on imprint_store_graded.
    var es := _store()
    var s0 := _surface()
    var dig := Vector3(CX, s0, CZ)                 # carve a crater on the surface
    es.stamp_sphere(dig, 5.0, SUBTRACT, 0, 1.0)
    var oc := SparseVoxelOctree.new()
    oc.setup(Vector3(CX - 128.0, s0 - 128.0, CZ - 128.0), 256.0)
    oc.imprint_store_graded(es, dig, 1.0, 32.0)
    assert_gt(oc.sample(Vector3(CX, s0 - 2.0, CZ)), 0.0, "the dig (carved crater) shows air in the render octree")
    assert_lt(oc.sample(Vector3(CX, s0 - 40.0, CZ)), 0.0, "unedited deep ground stays solid (generator)")


func test_serialize_round_trips() -> void:
    var es := _store()
    var s0 := _surface()
    var center := Vector3(CX, s0 - 5.0, CZ)
    es.stamp_sphere(center, 4.0, SUBTRACT, 0, 1.0)
    var far := Vector3(CX, s0 - 5.0, CZ + 30.0)

    var es2 := EditStore.new()
    es2.deserialize(es.serialize())
    assert_eq(es2.leaf_count(), es.leaf_count(), "leaf count survives the round trip")
    assert_almost_eq(es2.sample(center), es.sample(center), 0.01, "edited cell preserved")
    assert_true(es2.has_edit(center), "edit flag preserved")
    assert_almost_eq(es2.sample(far), es.sample(far), 0.01, "unedited still defers to the generator")
    assert_false(es2.has_edit(far), "unedited flag preserved")
