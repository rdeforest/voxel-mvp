extends GutTest

# A write next to an edited leaf coarser than its cell subdivides that leaf. Everything the write
# does not rewrite must read back bit for bit what it read before: the store's field is the same
# function outside the rewritten leaves, not a float32 re-rounding of it. The bug this pins is
# edit-store-subdivide-float32-neighbours: _subdivide re-stored every child's corners as the parent's
# trilerp rounded to float32, which moved samples outside the region by ~1e-7, and nested
# subdivisions (4 m -> 2 m -> 1 m) rounded twice. The store is the game's own (EditStoreManager:
# aligned root, the real generator), with a 4 m edited leaf at the surface.
# (Drafted by Claude, overnight 2026-09-26.)

const LEAF            := 4.0
const STEP            := 0.25  # band sample spacing: cell corners, centres and quarter points of every leaf
const ROOT_STATE_BYTE := 164   # header (7 doubles, 3 ints), then the root's origin, size, children, corners

var _store: EditStore
var _leaf:  Vector3   # origin of the 4 m edited leaf the writes straddle


func before_each() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store = manager.store
    var surface := EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    _leaf = Vector3(100.0, floorf(surface / LEAF) * LEAF, 100.0)
    _store.stamp_box(_leaf + Vector3.ONE * 2.2, Vector3(2.5, 3.0, 1.7), VoxelConstants.STORE_OP_UNION, 3, LEAF)


# A 1 m lattice over [origin, origin + 2] holding the store's field there, shifted by `shift`.
func _lattice(origin: Vector3, shift: float) -> PackedFloat32Array:
    var sdf := PackedFloat32Array()
    for z in 3:
        for y in 3:
            for x in 3:
                sdf.append(_store.sample(origin + Vector3(x, y, z)) + shift)

    return sdf


# Every band point in and around the 4 m leaf that the write at `lo` (a 2 m region) leaves outside
# its rewritten leaves. sample() reads the upper leaf on a boundary, so the rewritten footprint is
# the half-open box [lo, lo + 2).
func _band(lo: Vector3) -> Array[Vector3]:
    var hi  := lo + Vector3.ONE * 2.0
    var out: Array[Vector3] = []
    var n   := int((LEAF + 2.0) / STEP)
    for k in n + 1:
        for j in n + 1:
            for i in n + 1:
                var p := _leaf - Vector3.ONE + Vector3(i, j, k) * STEP
                var inside := p.x >= lo.x and p.x < hi.x and p.y >= lo.y and p.y < hi.y \
                    and p.z >= lo.z and p.z < hi.z
                if not inside:
                    out.append(p)

    return out


func _samples(points: Array[Vector3]) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    for p in points:
        out.append(_store.sample(p))
    return out


# The points whose sample moved, and the largest move, as a failure message.
func _moved(points: Array[Vector3], before: PackedFloat64Array) -> String:
    var count := 0
    var worst := 0.0
    for i in points.size():
        var now := _store.sample(points[i])
        if now != before[i]:
            count += 1
            worst = maxf(worst, absf(now - before[i]))
    return "" if count == 0 else "%d of %d band points moved, by up to %s" % [count, points.size(), worst]


func test_leaf_is_coarse_and_edited() -> void:
    var inner := _leaf + Vector3(1.5, 1.5, 1.5)
    assert_true(_store.has_edit(inner), "the 4 m leaf is edited")
    var sdf := _lattice(_leaf + Vector3.ONE, 0.0)
    assert_ne(_store.sample(inner), _store.sample(inner + Vector3(0.5, 0.0, 0.0)),
        "the field varies across the leaf (else a re-rounding could not show)")
    assert_eq(sdf.size(), 27)


# The write straddles the 4 m leaf's 2 m children (region [1, 3] inside [0, 4]), so it subdivides
# twice; every child it does not rewrite must keep the field it had.
func test_write_leaves_the_band_outside_its_region_bit_exact() -> void:
    for lo: Vector3 in [_leaf + Vector3.ONE, _leaf + Vector3(2.0, 0.0, 1.0), _leaf + Vector3(-1.0, 3.0, 2.0)]:
        var band   := _band(lo)
        var before := _samples(band)
        _store.write_region(_lattice(lo, -0.3), PackedByteArray(), 3, lo, 1.0)
        assert_eq(_moved(band, before), "", "write at %s: outside its region nothing moves" % lo)


# A stamp subdivides the same way: its 0.5 m leaves are those overlapping the brush box padded by a
# leaf, [lo + 0.1, lo + 1.9] here, so they fill [lo, lo + 2), and nothing outside them moves.
func test_stamp_leaves_the_band_outside_its_leaves_bit_exact() -> void:
    var lo     := _leaf + Vector3.ONE
    var band   := _band(lo)
    var before := _samples(band)
    var centre := _store.sample(lo + Vector3.ONE)
    _store.stamp_sphere(lo + Vector3.ONE, 0.4, VoxelConstants.STORE_OP_SUBTRACT, 0, 0.5)
    assert_ne(_store.sample(lo + Vector3.ONE), centre, "the stamp changes its centre (else this tests nothing)")
    assert_eq(_moved(band, before), "", "outside the stamp's leaves nothing moves")


func test_band_survives_a_serialize_round_trip() -> void:
    var lo := _leaf + Vector3.ONE
    _store.write_region(_lattice(lo, -0.3), PackedByteArray(), 3, lo, 1.0)
    var band   := _band(lo)
    var before := _samples(band)
    var copy   := EditStore.new()
    assert_true(copy.deserialize(_store.serialize()), "the blob loads")
    _store = copy
    assert_eq(_moved(band, before), "", "the reloaded store reads the same band")



# A blob whose node holds a field state this build doesn't know, or an inherited leaf with no field
# source above it, is refused whole: the store keeps what it held.
func test_unreadable_field_state_is_refused() -> void:
    _assert_blob_refused(9, "unknown field state 9")
    _assert_blob_refused(2, "an inherited leaf has no field source above it")


# `state` written over the root's field-state byte of an unedited store's blob (the root is a leaf).
func _assert_blob_refused(state: int, error: String) -> void:
    var fresh := EditStoreManager.new()
    fresh.setup()
    var blob  := fresh.store.serialize()
    blob[ROOT_STATE_BYTE] = state
    var probe := _leaf + Vector3.ONE * 2.0
    var held  := _store.sample(probe)
    assert_false(_store.deserialize(blob), "state %d is refused" % state)
    assert_engine_error(error, "refused loudly")
    assert_eq(_store.sample(probe), held, "the store keeps its own tree")

# A second identical write rewrites the same leaves with the same corners: nothing moves anywhere.
func test_identical_rewrite_changes_nothing() -> void:
    var lo  := _leaf + Vector3.ONE
    var sdf := _lattice(lo, -0.3)
    var first: Dictionary = _store.write_region_flips(sdf, PackedByteArray(), 3, lo, 1.0)
    assert_true(first.changed, "the first write changes its region")
    var band   := _band(_leaf + Vector3.ONE * 100.0)
    var before := _samples(band)
    var again: Dictionary = _store.write_region_flips(sdf, PackedByteArray(), 3, lo, 1.0)
    assert_false(again.changed, "the identical re-write reports no change")
    assert_eq(_moved(band, before), "", "and moves no sample in or around the leaf")


# The dry run splits the coarse leaf as the write does: a lattice that is the 4 m leaf's own field
# at its 1 m corners (read once, rounded once) is what the 1 m leaves it would write hold already.
func test_own_field_through_two_subdivisions_writes_nothing() -> void:
    var lo := _leaf + Vector3.ONE
    assert_false(_store.lattice_writes(_lattice(lo, 0.0), 3, lo, 1.0),
        "re-writing the 4 m leaf's own field at 1 m writes nothing")
