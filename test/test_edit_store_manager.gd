extends GutTest

# EditStoreManager persistence (Phase B S4): save_to/load_from blob the sparse store to
# disk with a magic+version header, replacing godot_voxel's SQLite stream. The C++
# serialize round-trip is pinned in test_edit_store.gd; this pins the GDScript file layer
# (header guard, in-place deserialize into the existing store).

const TMP := "user://test_editstore.tmp"
const SUBTRACT := 1


func _manager() -> EditStoreManager:
    var manager := EditStoreManager.new()
    manager.setup()
    return manager

func after_each() -> void:
    if FileAccess.file_exists(TMP):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_round_trips_edits_through_disk() -> void:
    var manager := _manager()
    var surface := EditStore.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    var center := Vector3(0.0, surface - 5.0, 0.0)
    manager.store.stamp_sphere(center, 4.0, SUBTRACT, 0, 1.0)
    assert_eq(manager.save_to(TMP), OK, "save writes the blob")

    var reloaded := _manager()
    assert_true(reloaded.load_from(TMP), "load accepts the matching-version blob")
    assert_eq(reloaded.store.leaf_count(), manager.store.leaf_count(), "leaf count survives disk round trip")
    assert_almost_eq(reloaded.store.sample(center), manager.store.sample(center), 0.01, "edited cell preserved")
    assert_true(reloaded.store.has_edit(center), "edit flag preserved")


func test_rejects_foreign_blob() -> void:
    var file := FileAccess.open(TMP, FileAccess.WRITE)
    file.store_32(0xDEADBEEF)   # wrong magic
    file.store_32(EditStoreManager.SAVE_VERSION)
    file.store_buffer(PackedByteArray([1, 2, 3]))
    file.close()
    var manager := _manager()
    assert_false(manager.load_from(TMP), "a blob with the wrong magic is skipped, not loaded")


func test_missing_file_returns_false() -> void:
    var manager := _manager()
    assert_false(manager.load_from("user://does_not_exist.tmp"), "missing file loads nothing")


func test_rejects_other_version_with_a_reason() -> void:
    var file := FileAccess.open(TMP, FileAccess.WRITE)
    file.store_32(EditStoreManager.SAVE_MAGIC)
    file.store_32(EditStoreManager.SAVE_VERSION + 1)
    file.store_buffer(PackedByteArray([1, 2, 3]))
    file.close()
    var manager := _manager()

    assert_false(manager.load_from(TMP), "a blob from another format version is skipped")
    assert_eq(EditStoreManager.refusal(TMP), "terrain save is format v%d; this build reads v1 to v%d"
        % [EditStoreManager.SAVE_VERSION + 1, EditStoreManager.SAVE_VERSION])


# (Drafted by Claude, overnight 2026-09-26.) SAVE_VERSION 2 marks blobs that may hold inherited
# leaves (field states 2 / 3), which a v1 build would misread as own-field leaves; this build reads
# v1 (states 0 / 1 only) as it always did, and refuses a version from the future or a damaged blob.

const HEADER_BYTES := 68   # EditStore blob header: 7 doubles, 3 ints
const NODE_BYTES   := 98
const STATE_OFFSET := 96


func _write(version: int, blob: PackedByteArray) -> void:
    var file := FileAccess.open(TMP, FileAccess.WRITE)
    file.store_32(EditStoreManager.SAVE_MAGIC)
    file.store_32(version)
    file.store_buffer(blob)

func _states(blob: PackedByteArray) -> Dictionary:
    var states := {}
    for node in (blob.size() - HEADER_BYTES) / NODE_BYTES:
        states[blob[HEADER_BYTES + node * NODE_BYTES + STATE_OFFSET]] = true

    return states

func _surface_point() -> Vector3:
    var surface := EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    return Vector3(100.0, floorf(surface / 4.0) * 4.0, 100.0)

# A 4 m edited leaf split by a 1 m write inside it: inherited leaves under a field source.
func _subdivided_manager() -> EditStoreManager:
    var manager := _manager()
    var leaf    := _surface_point()
    var lo      := leaf + Vector3.ONE
    manager.store.stamp_box(leaf + Vector3.ONE * 2.2, Vector3(2.5, 3.0, 1.7), VoxelConstants.STORE_OP_UNION, 3, 4.0)
    var sdf := PackedFloat32Array()
    for z in 3:
        for y in 3:
            for x in 3:
                sdf.append(manager.store.sample(lo + Vector3(x, y, z)) - 0.3)

    manager.store.write_region(sdf, PackedByteArray(), 3, lo, 1.0)
    return manager

func _probes() -> Array[Vector3]:
    var out: Array[Vector3] = []
    for i in 17:
        out.append(_surface_point() + Vector3(i, 16 - i, i * 0.37) * 0.25)

    return out

func _samples(manager: EditStoreManager) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    for p in _probes():
        out.append(manager.store.sample(p))

    return out


func test_v2_blob_with_inherited_leaves_round_trips() -> void:
    var manager := _subdivided_manager()
    assert_true(_states(manager.store.serialize()).has(2), "the store holds inherited leaves")
    assert_eq(manager.save_to(TMP), OK)
    assert_eq(FileAccess.get_file_as_bytes(TMP).decode_u32(4), 2,
        "it is saved as v2, which a v1 build refuses rather than misreading inherited leaves")

    var reloaded := _manager()
    assert_eq(EditStoreManager.refusal(TMP), "", "this build reads its own save")
    assert_true(reloaded.load_from(TMP), "and loads it")
    assert_eq(_samples(reloaded), _samples(manager), "bit for bit")
    assert_eq(reloaded.store.serialize(), manager.store.serialize(), "the tree itself survives")


func test_hand_built_v1_blob_still_loads() -> void:
    var manager := _manager()
    manager.store.stamp_sphere(_surface_point(), 3.0, SUBTRACT, 2, 1.0)
    var blob := manager.store.serialize()
    assert_eq(_states(blob).keys(), [0, 1], "a v1-shaped blob: no-field and own-field nodes only")
    _write(1, blob)

    var reloaded := _manager()
    assert_eq(EditStoreManager.refusal(TMP), "", "a v1 save is readable")
    assert_true(reloaded.load_from(TMP), "and loads")
    assert_eq(_samples(reloaded), _samples(manager), "reading the same field")


func test_refuses_versions_outside_one_to_current() -> void:
    for version in [0, 3, 99]:
        _write(version, _manager().store.serialize())
        assert_string_contains(EditStoreManager.refusal(TMP), "terrain save is format v%d" % version)
        assert_false(_manager().load_from(TMP), "v%d doesn't load" % version)


func test_damaged_blob_is_refused_with_its_reason() -> void:
    var manager := _subdivided_manager()
    var blob    := manager.store.serialize()
    _write(EditStoreManager.SAVE_VERSION, blob.slice(0, blob.size() - 40))

    assert_string_contains(EditStoreManager.refusal(TMP), "terrain save is damaged (EditStore blob is")
    var held := _samples(manager)
    assert_false(manager.load_from(TMP), "a truncated save doesn't load")
    assert_engine_error("truncated or corrupt", "load_from's deserialize refuses it loudly")
    assert_eq(_samples(manager), held, "and keeps the store as it was")
