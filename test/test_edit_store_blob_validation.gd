extends GutTest

# EditStore.deserialize refuses a blob that isn't a tree serialize could have written, before it
# touches the store: a child index out of range, pointing back up the tree or shared by two parents,
# a child that isn't its parent's octant, a state its place in the tree can't hold, or a blob cut
# short (save_to writes in place, so a crash mid-save truncates it). Each used to crash the engine
# inside deserialize (LocalVector's index check, or recursion round a cycle until the stack ran
# out) or read zeros past the end. It also refuses non-finite corners and generator params
# TerrainField can't sample, which used to load and then mesh NaN or freeze the first sample.
# The store is the game's own, with an edited 4 m leaf subdivided by a 1 m write, so the blob holds
# internal, field-source, inherited and own-field nodes.
# (Drafted by Claude, overnight 2026-09-26.)

const LEAF         := 4.0
const HEADER_BYTES := 68   # 7 doubles (root origin, root size, generator params), 3 ints (octaves, seed, count)
const NODE_BYTES   := 98   # origin + size (4 doubles), 8 child ints, 8 float corners, state and material bytes
const SIZE_OFFSET   := 24
const BASE_OFFSET   := 32
const AMP_OFFSET    := 40
const PERIOD_OFFSET := 48
const OCTAVE_OFFSET := 56
const CHILD_OFFSET  := 32
const CORNER_OFFSET := 64
const STATE_OFFSET  := 96

const NO_FIELD        := 0
const OWN_FIELD       := 1
const INHERITED_FIELD := 2
const FIELD_SOURCE    := 3

var _store:  EditStore
var _blob:   PackedByteArray
var _probes: Array[Vector3] = []
var _held:   PackedFloat64Array


func before_each() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store = manager.store
    var surface := EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    var leaf := Vector3(100.0, floorf(surface / LEAF) * LEAF, 100.0)
    _store.stamp_box(leaf + Vector3.ONE * 2.2, Vector3(2.5, 3.0, 1.7), VoxelConstants.STORE_OP_UNION, 3, LEAF)
    _write_shifted(leaf + Vector3.ONE, -0.3)
    _blob = _store.serialize()

    _probes.clear()
    for i in 9:
        _probes.append(leaf + Vector3(i, i * 0.7, 8 - i) * 0.5)
    _held = _samples()


# A 1 m write over [lo, lo + 2] of the store's own field shifted by `shift`: it subdivides the 4 m
# leaf, leaving inherited leaves around the rewritten ones.
func _write_shifted(lo: Vector3, shift: float) -> void:
    var sdf := PackedFloat32Array()
    for z in 3:
        for y in 3:
            for x in 3:
                sdf.append(_store.sample(lo + Vector3(x, y, z)) + shift)

    _store.write_region(sdf, PackedByteArray(), 3, lo, 1.0)


func _samples() -> PackedFloat64Array:
    var out := PackedFloat64Array()
    for p in _probes:
        out.append(_store.sample(p))

    return out


func _count() -> int:
    return (_blob.size() - HEADER_BYTES) / NODE_BYTES

func _at(node: int, offset: int) -> int:
    return HEADER_BYTES + node * NODE_BYTES + offset

func _child(node: int, j: int) -> int:
    return _blob.decode_s32(_at(node, CHILD_OFFSET + 4 * j))

func _with_child(node: int, j: int, value: int) -> PackedByteArray:
    var blob := _blob.duplicate()
    blob.encode_s32(_at(node, CHILD_OFFSET + 4 * j), value)
    return blob

func _last_internal() -> int:
    for node in range(_count() - 1, -1, -1):
        if _child(node, 0) >= 0:
            return node

    return -1

func _internal_without_field() -> int:
    for node in range(_count() - 1, 0, -1):
        if _child(node, 0) >= 0 and _blob[_at(node, STATE_OFFSET)] == NO_FIELD:
            return node

    return -1

func _first_leaf() -> int:
    for node in _count():
        if _child(node, 0) < 0:
            return node

    return -1

func _with_state(node: int, state: int) -> PackedByteArray:
    var blob := _blob.duplicate()
    blob[_at(node, STATE_OFFSET)] = state
    return blob

func _with_double(offset: int, value: float) -> PackedByteArray:
    var blob := _blob.duplicate()
    blob.encode_double(offset, value)
    return blob


func _assert_refused(blob: PackedByteArray, error: String, what: String) -> void:
    assert_false(_store.deserialize(blob), "%s is refused" % what)
    assert_engine_error(error, "%s is refused loudly" % what)
    assert_eq(_samples(), _held, "%s leaves the store as it was" % what)
    assert_eq(_store.serialize(), _blob, "%s leaves the tree itself untouched" % what)


func test_the_fixture_blob_has_every_node_kind() -> void:
    var states := {}
    for node in _count():
        states[_blob[_at(node, STATE_OFFSET)]] = true

    assert_eq(states.keys().size(), 4, "no field, own, inherited and field-source nodes all occur")
    assert_gt(_last_internal(), 0, "an internal node below the root")
    assert_true(_store.deserialize(_blob), "the untouched blob loads")
    assert_eq(_samples(), _held, "and reads back the same field")


func test_child_pointing_at_the_root_is_refused() -> void:
    _assert_refused(_with_child(0, 3, 0), "child", "a child index back to the root")


func test_child_pointing_at_itself_is_refused() -> void:
    var node := _last_internal()
    _assert_refused(_with_child(node, 5, node), "child", "a node its own child")


func test_child_pointing_back_up_the_tree_is_refused() -> void:
    var node := _last_internal()
    _assert_refused(_with_child(node, 2, 1), "child", "a child index to an earlier node")


func test_child_index_out_of_range_is_refused() -> void:
    _assert_refused(_with_child(0, 7, _count()), "child", "a child index one past the last node")
    _assert_refused(_with_child(0, 7, 0x7fffffff), "child", "a child index of 0x7fffffff")
    _assert_refused(_with_child(0, 7, -2), "child", "a negative child index on an internal node")


func test_child_shared_by_two_slots_is_refused() -> void:
    _assert_refused(_with_child(0, 1, _child(0, 0)), "child", "a child listed twice")


func test_child_off_its_parents_octant_is_refused() -> void:
    var blob := _blob.duplicate()
    blob.encode_double(_at(_child(0, 4), SIZE_OFFSET), LEAF)
    _assert_refused(blob, "octant", "a child the wrong size for its parent")


func test_leaf_holding_a_field_source_is_refused() -> void:
    var blob := _blob.duplicate()
    blob[_at(_count() - 1, STATE_OFFSET)] = FIELD_SOURCE
    _assert_refused(blob, "field", "a leaf marked as a field source")


func test_root_off_the_header_root_is_refused() -> void:
    var blob := _with_double(_at(0, SIZE_OFFSET), 2.0 * EditStoreManager.ROOT_SIZE)
    _assert_refused(blob, "root", "a root node that isn't the header's root cube")
    blob = _with_double(SIZE_OFFSET, 2.0 * EditStoreManager.ROOT_SIZE)
    _assert_refused(blob, "root", "a header root that isn't the root node's cube")


func test_empty_or_non_finite_root_is_refused() -> void:
    for size in [0.0, -EditStoreManager.ROOT_SIZE, NAN, INF]:
        var blob := _with_double(SIZE_OFFSET, size)
        blob.encode_double(_at(0, SIZE_OFFSET), size)
        _assert_refused(blob, "root", "a root cube of size %f in header and node alike" % size)


# write_region before f11d284 stored corners on internal nodes, so real v1 saves carry OWN_FIELD
# there; nothing reads it, and refusing it would lock those saves out.
func test_internal_node_holding_its_own_field_loads() -> void:
    var node := _internal_without_field()
    assert_gt(node, 0, "the fixture has an internal node below the root with no field")
    assert_true(_store.deserialize(_with_state(node, OWN_FIELD)), "an internal OWN_FIELD node loads")
    assert_eq(_samples(), _held, "and the field reads as it did")


func test_internal_node_inherited_is_refused() -> void:
    _assert_refused(_with_state(_last_internal(), INHERITED_FIELD), "inherited", "an internal node marked inherited")


func test_leaf_with_a_child_is_refused() -> void:
    _assert_refused(_with_child(_first_leaf(), 7, _count() - 1), "leaf", "a leaf listing a later node in a child slot")


func test_orphaned_nodes_are_refused() -> void:
    var blob := _blob.duplicate()
    var node := _internal_without_field()
    for j in 8:
        blob.encode_s32(_at(node, CHILD_OFFSET + 4 * j), -1)

    _assert_refused(blob, "no node's child", "an internal node turned leaf, orphaning its children")


func test_non_finite_corner_is_refused() -> void:
    for corner in [NAN, INF]:
        var blob := _blob.duplicate()
        blob.encode_float(_at(_count() - 1, CORNER_OFFSET + 4 * 5), corner)
        _assert_refused(blob, "non-finite corner", "a corner of %f" % corner)


func test_unsamplable_generator_is_refused() -> void:
    var cases := {
        "period 0":      _with_double(PERIOD_OFFSET, 0.0),
        "period -1000":  _with_double(PERIOD_OFFSET, -1000.0),
        "period NaN":    _with_double(PERIOD_OFFSET, NAN),
        "base infinite": _with_double(BASE_OFFSET, INF),
        "amp NaN":       _with_double(AMP_OFFSET, NAN),
    }
    for what in cases:
        _assert_refused(cases[what], "generator", "a generator with %s" % what)

    for octaves in [-1, 33, 0x7fffffff]:
        var blob := _blob.duplicate()
        blob.encode_s32(OCTAVE_OFFSET, octaves)
        _assert_refused(blob, "octaves", "a generator with %d octaves" % octaves)


func test_truncated_blob_is_refused() -> void:
    var cuts := [0, 10, HEADER_BYTES - 1, HEADER_BYTES, HEADER_BYTES + NODE_BYTES / 2,
        _at(1, CHILD_OFFSET + 6), _at(_count() - 3, 7), _blob.size() - 1]
    for cut in cuts:
        _assert_refused(_blob.slice(0, cut), "EditStore blob", "the blob cut at byte %d" % cut)


func test_trailing_bytes_are_refused() -> void:
    var blob := _blob.duplicate()
    blob.append(0)
    _assert_refused(blob, "EditStore blob", "a blob with a byte past its last node")
