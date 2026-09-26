extends GutTest

# StoreWrite.write: a caller that measured or previewed a work lattice writes THAT lattice, with the
# work's materials over every leaf's current one. The store is the game's (EditStoreManager: aligned
# root, the real generator), with a half-metre, second-material sphere so the written box spans
# several leaf levels and materials.

var _store: EditStore
var _at:    Vector3i   # a lattice point at the terrain surface, inside the sphere's box


func before_each() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store = manager.store
    var surface := EditStore.terrain_surface(0.0, 0.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    _at = Vector3i(0, int(surface), 0)
    _store.stamp_sphere(Vector3(_at) + Vector3(1.3, 0.2, 0.6), 1.6, VoxelConstants.STORE_OP_UNION, 3, 0.5)


func _work() -> Array[LatticeEdit]:
    return [
        LatticeEdit.new(_at, -0.4, 5),
        LatticeEdit.new(_at + Vector3i(2, 1, 1), 0.6),
    ] as Array[LatticeEdit]


func _materials(lat: SdfLattice) -> PackedByteArray:
    var out := PackedByteArray()
    for z in lat.dim:
        for y in lat.dim:
            for x in lat.dim:
                out.append(_store.material_at(lat.point(Vector3i(x, y, z))))
    return out


# The margin point is the current field in the lattice, so only a write of the handed array (not a
# rebuild from the work) can leave the nudged value there.
func test_write_lays_down_the_handed_lattice() -> void:
    var lat    := StoreWrite.lattice(_store, _work())
    var margin := Vector3i(0, 2, 1)
    lat.sdf[lat.index(margin)] = 0.75

    var box := StoreWrite.write(_store, lat, _work())

    assert_eq(_store.sample(lat.point(margin)), 0.75, "the nudged margin point is what the store holds")
    assert_almost_eq(_store.sample(Vector3(_at)), -0.4, 1e-6, "the work's own point is written")
    assert_eq(box, AABB(lat.region_lo, lat.region_hi - lat.region_lo), "the rewritten box is the lattice's")


func test_write_keeps_current_materials_except_the_works() -> void:
    var lat    := StoreWrite.lattice(_store, _work())
    var before := _materials(lat)
    var kinds  := {}
    for m in before:
        kinds[m] = true
    assert_gt(kinds.size(), 1, "the box spans more than one material (else this tests nothing)")

    StoreWrite.write(_store, lat, _work())

    var after   := _materials(lat)
    var painted := lat.index(_at - Vector3i(lat.origin))
    assert_eq(after[painted], 5, "the work's material lands on the leaf at its point")
    before[painted] = 5
    assert_eq(after, before, "every other leaf keeps the material it had")


func test_cells_is_write_of_a_fresh_lattice() -> void:
    var twin := _store.duplicate()
    var lat  := StoreWrite.lattice(twin, _work())

    StoreWrite.cells(_store, _work())
    StoreWrite.write(twin, lat, _work())

    assert_eq(_store.serialize(), twin.serialize(), "cells() writes what write() does with lattice()")


# A lattice off its cell grid would make the bulk material read land between lattice points.
func test_off_grid_lattice_is_refused() -> void:
    var lat    := StoreWrite.lattice(_store, _work())
    var before := _store.serialize()
    lat.origin += Vector3(0.5, 0.0, 0.0)

    assert_eq(StoreWrite.write(_store, lat, _work()), AABB(), "write() refuses")
    assert_push_error("not a whole number", "write() says why")
    assert_eq(StoreWrite.reshape(_store, lat), AABB(), "reshape() refuses")
    assert_push_error("not a whole number", "reshape() says why")
    assert_eq(_store.serialize(), before, "the store is untouched")


# The bulk read against the per-point reads it replaced, on every builder's lattices, over boxes
# that span 1 / 0.5 / 0.25 m leaves and several materials.
func test_current_materials_are_the_per_point_reads_on_every_builder() -> void:
    _store.stamp_sphere(Vector3(_at) + Vector3(-1.1, 0.4, -0.7), 1.2, VoxelConstants.STORE_OP_UNION, 4, 0.25)
    var lattices: Array[SdfLattice] = [StoreWrite.lattice(_store, _work())]
    for offset: Vector3 in [Vector3.ZERO, Vector3(-1.4, 0.3, -0.2), Vector3(0.7, -0.6, 1.9)]:
        var at := Vector3(_at) + offset
        for radius: float in [1.5, 3.0]:
            lattices.append(SdfLattice.predicted(_store.predict_bell(at, radius, 0.4 * radius)))
            lattices.append(SdfLattice.predicted(_store.predict_bell(at, radius, -0.4 * radius)))
            lattices.append(SdfLattice.predicted(_store.predict_flatten(at, Vector3(0.3, 1.0, -0.2).normalized(), radius)))

    var multi := 0
    for lat in lattices:
        assert_not_null(lat, "every brush here writes (a refusal would skip its lattice)")
        if lat == null:
            continue

        var expected := _materials(lat)
        assert_eq(StoreWrite._current_materials(_store, lat), expected, "lattice at %s" % lat.origin)
        if Array(expected).any(func(m: int) -> bool: return m != expected[0]):
            multi += 1
    assert_gt(multi, 0, "some lattice spans more than one material (else the order is untested)")


func test_reshape_keeps_every_current_material() -> void:
    var normal := Vector3(0.3, 1.0, -0.2).normalized()
    var lat    := SdfLattice.predicted(_store.predict_flatten(Vector3(_at) + Vector3(1.0, 0.5, 0.5), normal, 3.0))
    assert_not_null(lat, "the flatten writes")
    var before := _materials(lat)

    StoreWrite.reshape(_store, lat)

    assert_eq(_materials(lat), before, "no leaf's material changes")
