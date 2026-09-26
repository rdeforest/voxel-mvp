extends GutTest

# SavedWorld reads the WorldSnapshot + EditStore blob as one save. A half this build can't
# read refuses the whole pair (the snapshot's tracked voxels describe the blob), with a
# reason the world reports, and F5 then refuses to overwrite the files instead of silently
# replacing a save the player never saw load.

const SNAPSHOT  := "user://test_saved_world.snapshot"
const EDITSTORE := "user://test_saved_world.editstore"
const SUBTRACT  := 1


func after_each() -> void:
    for path in [SNAPSHOT, EDITSTORE]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_snapshot(version: int) -> void:
    var file := FileAccess.open(SNAPSHOT, FileAccess.WRITE)
    file.store_string(var_to_str({"version": version, "player": {}, "voxels": []}))

func _write_blob_header(magic: int, version: int) -> void:
    var file := FileAccess.open(EDITSTORE, FileAccess.WRITE)
    file.store_32(magic)
    file.store_32(version)
    file.store_buffer(PackedByteArray([1, 2, 3]))

func _read() -> SavedWorld:
    return SavedWorld.read(SNAPSHOT, EDITSTORE)


func test_readable_pair_has_no_refusal() -> void:
    _write_snapshot(WorldSnapshot.VERSION)
    _write_blob_header(EditStoreManager.SAVE_MAGIC, EditStoreManager.SAVE_VERSION)
    var saved := _read()

    assert_eq(saved.refusal, "", "a current-format pair loads")
    assert_eq(saved.snapshot.get("version"), WorldSnapshot.VERSION, "the snapshot is parsed once, here")


func test_no_save_on_disk_is_not_a_refusal() -> void:
    var saved := _read()

    assert_eq(saved.refusal, "", "a first run has nothing to refuse")
    assert_true(saved.snapshot.is_empty())


func test_blob_version_bump_refuses_the_whole_pair() -> void:
    _write_snapshot(WorldSnapshot.VERSION)
    _write_blob_header(EditStoreManager.SAVE_MAGIC, EditStoreManager.SAVE_VERSION + 1)
    var saved := _read()

    assert_string_contains(saved.refusal, "terrain save is format v%d" % (EditStoreManager.SAVE_VERSION + 1))
    assert_true(saved.snapshot.is_empty(), "the snapshot half isn't applied over fresh terrain")
    assert_false(saved.load_into(null, null), "nothing loads from a refused pair")


func test_foreign_blob_refuses() -> void:
    _write_blob_header(0xDEADBEEF, EditStoreManager.SAVE_VERSION)

    assert_string_contains(_read().refusal, "not an EditStore blob")


func test_newer_snapshot_refuses_the_whole_pair() -> void:
    _write_snapshot(WorldSnapshot.VERSION + 1)
    _write_blob_header(EditStoreManager.SAVE_MAGIC, EditStoreManager.SAVE_VERSION)

    assert_string_contains(_read().refusal, "world snapshot is format v%d" % (WorldSnapshot.VERSION + 1))


func test_refused_pair_is_not_overwritten() -> void:
    _write_snapshot(WorldSnapshot.VERSION)
    _write_blob_header(EditStoreManager.SAVE_MAGIC, EditStoreManager.SAVE_VERSION + 1)
    var blob_before     := FileAccess.get_file_as_bytes(EDITSTORE)
    var snapshot_before := FileAccess.get_file_as_string(SNAPSHOT)

    var problem := _read().save(null, null)

    assert_string_contains(problem, "not overwriting")
    assert_eq(FileAccess.get_file_as_bytes(EDITSTORE), blob_before, "terrain save untouched")
    assert_eq(FileAccess.get_file_as_string(SNAPSHOT), snapshot_before, "world snapshot untouched")


func _world_stub() -> Node:
    var world     := Node.new()
    var integrity := StructuralIntegrity.new()
    var player    := CharacterBody3D.new()
    integrity.name = "StructuralIntegrity"
    player.name    = "Player"
    world.add_child(integrity)
    world.add_child(player)
    add_child_autofree(world)
    return world

func _dig_center() -> Vector3:
    var surface := EditStore.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    return Vector3(0.0, surface - 5.0, 0.0)

func _edited_manager() -> EditStoreManager:
    var manager := EditStoreManager.new()
    manager.setup()
    manager.store.stamp_sphere(_dig_center(), 4.0, SUBTRACT, 0, 1.0)
    return manager


func test_readable_pair_applies_both_halves() -> void:
    var voxel := Vector3i(4, 5, 6)
    var file  := FileAccess.open(SNAPSHOT, FileAccess.WRITE)
    file.store_string(var_to_str({"version": WorldSnapshot.VERSION, "player": {},
        "voxels": [{"pos": voxel, "material": "Stone", "support": 0.75}]}))
    file.close()
    assert_eq(_edited_manager().save_to(EDITSTORE), OK)

    var world    := _world_stub()
    var reloaded := EditStoreManager.new()
    reloaded.setup()

    assert_false(reloaded.store.has_edit(_dig_center()), "a fresh store has no edit there")
    assert_true(_read().load_into(world, reloaded), "a readable pair reports it loaded")
    var support: TerrainSupport = world.get_node("StructuralIntegrity").terrain_support
    assert_true(support.voxel_data.has(voxel), "the snapshot's tracked voxel is restored")
    assert_almost_eq(support.voxel_data[voxel].support, 0.75, 1e-6, "with its saved support")
    assert_true(reloaded.store.has_edit(_dig_center()), "the blob's edit is loaded")
