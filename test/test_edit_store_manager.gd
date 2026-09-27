extends GutTest

# EditStoreManager persistence (Phase B S4): save_to/load_from blob the sparse store to
# disk with a magic+version header, replacing godot_voxel's SQLite stream. The C++
# serialize round-trip is pinned in test_edit_store.gd; this pins the GDScript file layer
# (header guard, in-place deserialize into the existing store).

const TMP      := "user://test_editstore.tmp"
const SUBTRACT := 1
const SAVE_ID  := -9001   # negative: the header stores it as an unsigned 64-bit field


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
    assert_eq(manager.save_to(TMP, SAVE_ID), OK, "save writes the blob")

    var reloaded := _manager()
    assert_true(reloaded.load_from(TMP), "load accepts the matching-version blob")
    assert_eq(reloaded.store.leaf_count(), manager.store.leaf_count(), "leaf count survives disk round trip")
    assert_almost_eq(reloaded.store.sample(center), manager.store.sample(center), 0.01, "edited cell preserved")
    assert_true(reloaded.store.has_edit(center), "edit flag preserved")


func test_rejects_foreign_blob() -> void:
    var file := FileAccess.open(TMP, FileAccess.WRITE)
    file.store_32(0xDEADBEEF)   # wrong magic
    file.store_32(EditStoreManager.SAVE_VERSION)
    file.store_64(SAVE_ID)
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
    file.store_64(SAVE_ID)
    file.store_buffer(PackedByteArray([1, 2, 3]))
    file.close()
    var manager := _manager()

    assert_false(manager.load_from(TMP), "a blob from another format version is skipped")
    assert_eq(EditStoreManager.refusal(TMP), "terrain save is format v%d; this build reads only v%d"
        % [EditStoreManager.SAVE_VERSION + 1, EditStoreManager.SAVE_VERSION])


# (Drafted by Claude, overnight 2026-09-26; one format only since 2026-09-27.) A blob round-trips
# inherited leaves (field states 2 / 3) exactly, and this build refuses any version but its own, and
# a damaged blob.

const HEADER_BYTES := 68   # EditStore blob header: 7 doubles, 3 ints
const NODE_BYTES   := 98
const STATE_OFFSET := 96


func _write(version: int, blob: PackedByteArray) -> void:
    var file := FileAccess.open(TMP, FileAccess.WRITE)
    file.store_32(EditStoreManager.SAVE_MAGIC)
    file.store_32(version)
    file.store_64(SAVE_ID)
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


func test_blob_with_inherited_leaves_round_trips() -> void:
    var manager := _subdivided_manager()
    assert_true(_states(manager.store.serialize()).has(2), "the store holds inherited leaves")
    assert_eq(manager.save_to(TMP, SAVE_ID), OK)
    assert_eq(FileAccess.get_file_as_bytes(TMP).decode_u32(4), EditStoreManager.SAVE_VERSION,
        "it is saved as the current version")

    var reloaded := _manager()
    assert_eq(EditStoreManager.refusal(TMP), "", "this build reads its own save")
    assert_eq(EditStoreManager.save_id(TMP), SAVE_ID, "the save id survives, sign and all")
    assert_true(reloaded.load_from(TMP), "and loads it")
    assert_eq(_samples(reloaded), _samples(manager), "bit for bit")
    assert_eq(reloaded.store.serialize(), manager.store.serialize(), "the tree itself survives")


func test_refuses_every_version_but_the_current_one() -> void:
    for version in [0, 1, 2, EditStoreManager.SAVE_VERSION + 1, 99]:
        _write(version, _manager().store.serialize())
        assert_eq(EditStoreManager.refusal(TMP), "terrain save is format v%d; this build reads only v%d"
            % [version, EditStoreManager.SAVE_VERSION])
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
