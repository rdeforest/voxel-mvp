extends GutTest

# EditStore.leaf_info: the leaf that holds a point, as the probe reports it (doc 22, the instrument
# layer). Each leaf's corners must be what the store reads at them from inside that leaf: the
# generator's samples for an unedited leaf, the leaf's own corners for one that holds its field, and
# its source's field rounded to float32 for an inherited one. The store is the game's own
# (EditStoreManager: the real root and generator), with a 4 m edit at the surface.
# (Drafted by Claude, overnight 2026-09-27.)

const COARSE := 4.0
const PAINT  := 5

# A 4 m lattice's corners, chosen so a 2 m child's corners are not float32 values.
const COARSE_SDF := [0.1, -0.7, 0.3, -1.3, 0.9, -0.2, 1.1, -0.35]

var _store: EditStore
var _leaf:  Vector3   # origin of the 4 m cube at the surface the edits land in


func before_each() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store = manager.store
    var surface := EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    _leaf = Vector3(100.0, floorf(surface / COARSE) * COARSE, 100.0)


static func _f32(x: float) -> float:
    return PackedFloat32Array([x])[0]

static func _corner(info: Dictionary, k: int) -> Vector3:
    return info.origin + CubeGeometry.corner(k) * info.size

# What the store reads at each of the leaf's corners from `inside` it, rounded to float32 when
# `rounded` (a stored corner is a float32).
func _read_corners(info: Dictionary, inside: Vector3, rounded: bool) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    for k in 8:
        var v := _store.sample_toward(_corner(info, k), inside)
        out.append(_f32(v) if rounded else v)
    return out

func _write_coarse() -> void:
    _store.write_region(PackedFloat32Array(COARSE_SDF), PackedByteArray([PAINT]), 2, _leaf, COARSE)

func _write_fine(origin: Vector3, value: float) -> void:
    var sdf := PackedFloat32Array()
    sdf.resize(8)
    sdf.fill(value)
    _store.write_region(sdf, PackedByteArray([PAINT + 1]), 2, origin, 1.0)


func test_an_unedited_store_is_one_generator_leaf() -> void:
    var p    := _leaf + Vector3.ONE * 0.5
    var info := _store.leaf_info(p)

    assert_eq(info.origin, EditStoreManager.ROOT_ORIGIN, "the root is the only leaf")
    assert_eq(info.size, EditStoreManager.ROOT_SIZE)
    assert_eq(info.field, EditStore.NO_FIELD, "the generator's")
    assert_false(info.has("material"), "an unedited leaf holds no material")
    assert_false(info.has("source_origin"))
    assert_eq(info.corners, _read_corners(info, p, false), "its corners are the generator's samples")


func test_a_written_leaf_holds_its_own_field() -> void:
    _write_coarse()
    var p    := _leaf + Vector3(1.5, 2.5, 3.5)
    var info := _store.leaf_info(p)

    assert_eq(info.origin, _leaf)
    assert_eq(info.size, COARSE)
    assert_eq(info.field, EditStore.OWN_FIELD)
    assert_eq(info.material, PAINT)
    assert_false(info.has("source_origin"), "it reads its own field")
    assert_eq(info.corners, PackedFloat64Array(COARSE_SDF.map(_f32)), "the corners written")
    assert_eq(info.corners, _read_corners(info, p, false), "which the store reads at them")


# A 1 m write in the 4 m leaf's low corner subdivides it; the 2 m leaf at its far corner still reads
# the 4 m field, and holds it at its own corners rounded to float32.
func test_a_leaf_next_to_a_finer_write_inherits_the_coarse_field() -> void:
    _write_coarse()
    _write_fine(_leaf, -2.0)
    var p    := _leaf + Vector3.ONE * 3.5
    var info := _store.leaf_info(p)

    assert_eq(info.origin, _leaf + Vector3.ONE * 2.0)
    assert_eq(info.size, 2.0)
    assert_eq(info.field, EditStore.INHERITED_FIELD)
    assert_eq(info.material, PAINT, "the subdivided leaf's material")
    assert_eq(info.source_origin, _leaf, "its source is the subdivided 4 m leaf")
    assert_eq(info.source_size, COARSE)
    assert_eq(info.corners, _read_corners(info, p, true), "the source's field at its corners, to float32")
    assert_ne(info.corners, _read_corners(info, p, false), "precondition: the rounding shows")

    var fine := _store.leaf_info(_leaf + Vector3.ONE * 0.5)
    assert_eq([fine.origin, fine.size, fine.field], [_leaf, 1.0, EditStore.OWN_FIELD], "the written 1 m leaf")
    assert_eq(fine.corners, _read_corners(fine, _leaf + Vector3.ONE * 0.5, false))


# Subdivision also makes unedited leaves: a write in an unedited region leaves its siblings the
# generator's, smaller than the root.
func test_an_unedited_sibling_of_an_edit_reads_the_generator() -> void:
    _write_fine(_leaf, -2.0)
    var p    := _leaf + Vector3(1.5, 0.5, 0.5)
    var info := _store.leaf_info(p)

    assert_eq([info.origin, info.size], [_leaf + Vector3(1, 0, 0), 1.0], "the 1 m sibling")
    assert_eq(info.field, EditStore.NO_FIELD)
    assert_false(info.has("material"))
    assert_eq(info.corners, _read_corners(info, p, false), "the generator's samples at its corners")


func test_outside_the_root_there_is_no_leaf() -> void:
    assert_eq(_store.leaf_info(EditStoreManager.ROOT_ORIGIN - Vector3.ONE), {})
