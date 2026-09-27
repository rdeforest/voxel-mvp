extends GutTest

# SavedWorld reads the WorldSnapshot + EditStore blob as one save. The pair loads only when both
# halves are present, in this build's format, and carry the same save id; anything else refuses
# the whole pair with a reason the world reports, and F5 then refuses to overwrite the files
# instead of silently replacing a save the player never saw load. A save writes both halves under
# temporary names and renames them into place; a committed save a crash interrupted is finished
# by the next read.

const SNAPSHOT  := "user://test_saved_world.snapshot"
const EDITSTORE := "user://test_saved_world.editstore"
const SUBTRACT  := 1
const SAVE_ID   := -4242   # negative on purpose: the blob stores it as an unsigned 64-bit field
const OTHER_ID  := 77


class PlayerStub:
    extends CharacterBody3D

    var build_state       := BuildState.new()
    var tool_index        := 2
    var _activity_indices: Array[int] = [1, 0, 3]


    func _init() -> void:
        var head := Node3D.new()
        head.name = "Head"
        add_child(head)


func after_each() -> void:
    for path in [SNAPSHOT, EDITSTORE]:
        for file in [path, path + SavedWorld.TMP_SUFFIX]:
            var absolute := ProjectSettings.globalize_path(file)
            if FileAccess.file_exists(file) or DirAccess.dir_exists_absolute(absolute):
                DirAccess.remove_absolute(absolute)


func _write_snapshot(version: int, save_id: int, path := SNAPSHOT) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(var_to_str({"version": version, "save_id": save_id, "player": {}, "voxels": []}))

func _write_blob_header(magic: int, version: int, save_id := SAVE_ID) -> void:
    var file := FileAccess.open(EDITSTORE, FileAccess.WRITE)
    file.store_32(magic)
    file.store_32(version)
    file.store_64(save_id)
    file.store_buffer(PackedByteArray([1, 2, 3]))

func _write_pair(save_id := SAVE_ID) -> void:
    _write_snapshot(WorldSnapshot.VERSION, save_id)
    assert_eq(_edited_manager().save_to(EDITSTORE, save_id), OK)

func _read() -> SavedWorld:
    return SavedWorld.read(SNAPSHOT, EDITSTORE)

func _assert_refused_and_kept(saved: SavedWorld, reason: String) -> void:
    var snapshot_before := FileAccess.get_file_as_bytes(SNAPSHOT)
    var blob_before     := FileAccess.get_file_as_bytes(EDITSTORE)

    assert_string_contains(saved.refusal, reason)
    assert_true(saved.snapshot.is_empty(), "the snapshot half isn't applied")
    assert_false(saved.load_into(null, null), "nothing loads from a refused pair")
    assert_string_contains(saved.save(null, null), "not overwriting")
    assert_eq(FileAccess.get_file_as_bytes(SNAPSHOT), snapshot_before, "world snapshot kept as it was")
    assert_eq(FileAccess.get_file_as_bytes(EDITSTORE), blob_before, "terrain save kept as it was")


func test_readable_pair_has_no_refusal() -> void:
    _write_pair()
    var saved := _read()

    assert_eq(saved.refusal, "", "a current-format pair loads")
    assert_eq(saved.snapshot.get("version"), WorldSnapshot.VERSION, "the snapshot is parsed once, here")


func test_no_save_on_disk_is_not_a_refusal() -> void:
    var saved := _read()

    assert_eq(saved.refusal, "", "a first run has nothing to refuse")
    assert_true(saved.snapshot.is_empty())


func test_blob_version_bump_refuses_the_whole_pair() -> void:
    _write_snapshot(WorldSnapshot.VERSION, SAVE_ID)
    _write_blob_header(EditStoreManager.SAVE_MAGIC, EditStoreManager.SAVE_VERSION + 1)

    _assert_refused_and_kept(_read(), "terrain save is format v%d" % (EditStoreManager.SAVE_VERSION + 1))


func test_foreign_blob_refuses() -> void:
    _write_snapshot(WorldSnapshot.VERSION, SAVE_ID)
    _write_blob_header(0xDEADBEEF, EditStoreManager.SAVE_VERSION)

    assert_string_contains(_read().refusal, "not an EditStore blob")


func test_newer_snapshot_refuses_the_whole_pair() -> void:
    _write_snapshot(WorldSnapshot.VERSION + 1, SAVE_ID)
    _write_blob_header(EditStoreManager.SAVE_MAGIC, EditStoreManager.SAVE_VERSION)

    assert_string_contains(_read().refusal, "world snapshot is format v%d" % (WorldSnapshot.VERSION + 1))


func test_older_snapshot_refuses_the_whole_pair() -> void:
    _write_snapshot(WorldSnapshot.VERSION - 1, SAVE_ID)
    assert_eq(_edited_manager().save_to(EDITSTORE, SAVE_ID), OK)

    _assert_refused_and_kept(_read(), "world snapshot is format v%d; this build reads only v%d"
        % [WorldSnapshot.VERSION - 1, WorldSnapshot.VERSION])


func test_lone_snapshot_is_refused_and_kept() -> void:
    _write_snapshot(WorldSnapshot.VERSION, SAVE_ID)
    var saved := _read()

    assert_string_contains(saved.refusal, "no terrain save beside it")
    assert_true(saved.snapshot.is_empty(), "its support records aren't applied over fresh terrain")
    assert_string_contains(saved.save(null, null), "not overwriting")
    assert_false(FileAccess.file_exists(EDITSTORE), "F5 doesn't write a blob beside it")


func test_lone_blob_is_refused_and_kept() -> void:
    assert_eq(_edited_manager().save_to(EDITSTORE, SAVE_ID), OK)
    var saved := _read()

    assert_string_contains(saved.refusal, "no world snapshot beside it")
    assert_false(saved.load_into(null, null), "its terrain doesn't load without its support records")
    assert_string_contains(saved.save(null, null), "not overwriting")
    assert_false(FileAccess.file_exists(SNAPSHOT), "F5 doesn't write a snapshot beside it")


func test_halves_from_different_saves_are_refused_and_kept() -> void:
    _write_snapshot(WorldSnapshot.VERSION, OTHER_ID)
    assert_eq(_edited_manager().save_to(EDITSTORE, SAVE_ID), OK)

    _assert_refused_and_kept(_read(), "come from different saves")


func _world_stub() -> Node:
    var world     := Node.new()
    var integrity := StructuralIntegrity.new()
    var player    := PlayerStub.new()
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

func _edited_manager(center := _dig_center()) -> EditStoreManager:
    var manager := EditStoreManager.new()
    manager.setup()
    manager.store.stamp_sphere(center, 4.0, SUBTRACT, 0, 1.0)
    return manager

func _fresh_manager() -> EditStoreManager:
    var manager := EditStoreManager.new()
    manager.setup()
    return manager


func test_readable_pair_applies_both_halves() -> void:
    var voxel := Vector3i(4, 5, 6)
    var file  := FileAccess.open(SNAPSHOT, FileAccess.WRITE)
    file.store_string(var_to_str({"version": WorldSnapshot.VERSION, "save_id": SAVE_ID, "player": {},
        "voxels": [{"pos": voxel, "material": "Stone", "support": 0.75}]}))
    file.close()
    assert_eq(_edited_manager().save_to(EDITSTORE, SAVE_ID), OK)

    var world    := _world_stub()
    var reloaded := _fresh_manager()

    assert_false(reloaded.store.has_edit(_dig_center()), "a fresh store has no edit there")
    assert_true(_read().load_into(world, reloaded), "a readable pair reports it loaded")
    var support: TerrainSupport = world.get_node("StructuralIntegrity").terrain_support
    assert_true(support.voxel_data.has(voxel), "the snapshot's tracked voxel is restored")
    assert_almost_eq(support.voxel_data[voxel].support, 0.75, 1e-6, "with its saved support")
    assert_true(reloaded.store.has_edit(_dig_center()), "the blob's edit is loaded")


# (Drafted by Claude, overnight 2026-09-26.) A blob with a good header but a body deserialize would
# refuse (truncated by a crash mid-save, say) refuses the pair at read time, like a version bump:
# before, the snapshot half applied over fresh terrain, and F5 then overwrote the damaged blob.
func test_damaged_blob_refuses_the_whole_pair() -> void:
    _write_snapshot(WorldSnapshot.VERSION, SAVE_ID)
    _write_blob_header(EditStoreManager.SAVE_MAGIC, EditStoreManager.SAVE_VERSION)

    _assert_refused_and_kept(_read(), "terrain save is damaged")


# --- writing the pair (drafted by Claude, overnight 2026-09-27) ---

func test_save_writes_a_matching_pair_and_no_temporaries() -> void:
    var source := _world_stub()
    source.get_node("Player").tool_index = 5
    assert_eq(_read().save(source, _edited_manager()), "", "a first save succeeds")

    for path in [SNAPSHOT, EDITSTORE]:
        assert_true(FileAccess.file_exists(path), "%s is in place" % path)
        assert_false(FileAccess.file_exists(path + SavedWorld.TMP_SUFFIX), "no temporary left beside it")

    var reread := _read()
    assert_eq(reread.refusal, "", "the pair it wrote reads back")
    assert_eq(reread.snapshot["save_id"], EditStoreManager.save_id(EDITSTORE), "both halves carry one id")

    var world    := _world_stub()
    var reloaded := _fresh_manager()
    assert_true(reread.load_into(world, reloaded), "and loads")
    assert_eq(world.get_node("Player").tool_index, 5, "the snapshot half applied")
    assert_true(reloaded.store.has_edit(_dig_center()), "the blob half loaded")


func test_each_save_gets_its_own_id() -> void:
    assert_eq(_read().save(_world_stub(), _edited_manager()), "")
    var first := EditStoreManager.save_id(EDITSTORE)
    assert_eq(_read().save(_world_stub(), _edited_manager()), "")

    assert_ne(EditStoreManager.save_id(EDITSTORE), first, "a later save can't pass for an earlier one's half")


func test_failed_blob_write_leaves_the_previous_pair() -> void:
    _write_pair()
    var snapshot_before := FileAccess.get_file_as_bytes(SNAPSHOT)
    var blob_before     := FileAccess.get_file_as_bytes(EDITSTORE)
    DirAccess.make_dir_absolute(ProjectSettings.globalize_path(EDITSTORE + SavedWorld.TMP_SUFFIX))

    assert_string_contains(_read().save(_world_stub(), _edited_manager()), "terrain:", "the failure is reported")
    assert_eq(FileAccess.get_file_as_bytes(SNAPSHOT), snapshot_before, "the snapshot isn't replaced")
    assert_eq(FileAccess.get_file_as_bytes(EDITSTORE), blob_before, "nor the blob")
    assert_eq(_read().refusal, "", "the previous save still loads")


# The pair a save wrote under temporary names, with the new edit somewhere the old pair lacks.
func _write_pending_pair(new_edit: Vector3) -> void:
    _write_snapshot(WorldSnapshot.VERSION, OTHER_ID, SNAPSHOT + SavedWorld.TMP_SUFFIX)
    assert_eq(_edited_manager(new_edit).save_to(EDITSTORE + SavedWorld.TMP_SUFFIX, OTHER_ID), OK)

func _assert_finished_as_the_new_save(new_edit: Vector3) -> void:
    var saved := _read()
    for path in [SNAPSHOT, EDITSTORE]:
        assert_false(FileAccess.file_exists(path + SavedWorld.TMP_SUFFIX), "%s's temporary is renamed in" % path)
    _assert_loads_as_the_new_save(saved, new_edit)

func _assert_loads_as_the_new_save(saved: SavedWorld, new_edit: Vector3) -> void:
    assert_eq(saved.refusal, "", "the interrupted save reads as a whole pair")
    assert_eq(saved.snapshot["save_id"], OTHER_ID, "the newer save")

    var reloaded := _fresh_manager()
    assert_true(saved.load_into(_world_stub(), reloaded))
    assert_true(reloaded.store.has_edit(new_edit), "with the newer save's terrain")


func test_crash_between_the_renames_finishes_the_save() -> void:
    var new_edit := _dig_center() + Vector3(40, 0, 0)
    _write_pair()
    _write_pending_pair(new_edit)
    DirAccess.rename_absolute(SNAPSHOT + SavedWorld.TMP_SUFFIX, SNAPSHOT)

    _assert_finished_as_the_new_save(new_edit)


func test_crash_before_the_renames_finishes_the_save() -> void:
    var new_edit := _dig_center() + Vector3(40, 0, 0)
    _write_pair()
    _write_pending_pair(new_edit)

    _assert_finished_as_the_new_save(new_edit)


# Windows' rename removes the target before moving the source in, so a crash can land between.
func test_crash_inside_a_non_atomic_rename_finishes_the_save() -> void:
    var new_edit := _dig_center() + Vector3(40, 0, 0)
    _write_pair()
    _write_pending_pair(new_edit)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SNAPSHOT))

    _assert_finished_as_the_new_save(new_edit)


func test_first_save_crash_between_the_renames_finishes_the_save() -> void:
    var new_edit := _dig_center() + Vector3(40, 0, 0)
    _write_pending_pair(new_edit)
    DirAccess.rename_absolute(SNAPSHOT + SavedWorld.TMP_SUFFIX, SNAPSHOT)

    _assert_finished_as_the_new_save(new_edit)


func test_crash_while_writing_the_blob_keeps_the_previous_save() -> void:
    _write_pair()
    _write_pending_pair(_dig_center() + Vector3(40, 0, 0))
    var blob_tmp := EDITSTORE + SavedWorld.TMP_SUFFIX
    var partial  := FileAccess.get_file_as_bytes(blob_tmp)
    FileAccess.open(blob_tmp, FileAccess.WRITE).store_buffer(partial.slice(0, partial.size() - 40))

    var saved := _read()
    assert_eq(saved.refusal, "", "the previous pair is untouched")
    assert_eq(saved.snapshot["save_id"], SAVE_ID, "and is what loads")
    assert_true(FileAccess.file_exists(blob_tmp), "the uncommitted temporary is left for the next save")


# --- a commit is what reads back (drafted by Claude, overnight 2026-09-27) ---

# Truncates one temporary after an otherwise successful write: FileAccess drops a failure flushing a
# file's tail at close, so a write can report success and leave a short file.
class ShortWriteSave:
    extends SavedWorld

    var truncate: String


    func _init(p_snapshot_path: String, p_editstore_path: String, p_truncate: String) -> void:
        super(p_snapshot_path, p_editstore_path)
        truncate = p_truncate


    func _write_temporaries(world: Node, edit_store: EditStoreManager, save_id: int) -> String:
        var problem := super(world, edit_store, save_id)
        var written := FileAccess.get_file_as_bytes(truncate)
        FileAccess.open(truncate, FileAccess.WRITE).store_buffer(written.slice(0, written.size() / 2))
        return problem


func _assert_short_write_keeps_the_previous_pair(truncate: String) -> void:
    _write_pair()
    var snapshot_before := FileAccess.get_file_as_bytes(SNAPSHOT)
    var blob_before     := FileAccess.get_file_as_bytes(EDITSTORE)
    var saving          := ShortWriteSave.new(SNAPSHOT, EDITSTORE, truncate)

    assert_string_contains(saving.save(_world_stub(), _edited_manager()), "didn't read back whole")
    assert_eq(FileAccess.get_file_as_bytes(SNAPSHOT), snapshot_before, "the snapshot isn't replaced")
    assert_eq(FileAccess.get_file_as_bytes(EDITSTORE), blob_before, "nor the blob")

    var saved := _read()
    assert_eq(saved.refusal, "", "the previous save still loads")
    assert_eq(saved.snapshot.get("save_id"), SAVE_ID, "and is what loads")


func test_short_snapshot_write_keeps_the_previous_pair() -> void:
    _assert_short_write_keeps_the_previous_pair(SNAPSHOT + SavedWorld.TMP_SUFFIX)


func test_short_blob_write_keeps_the_previous_pair() -> void:
    _assert_short_write_keeps_the_previous_pair(EDITSTORE + SavedWorld.TMP_SUFFIX)


# A blob rename that failed in-session leaves the save committed but unfinished; the next F5
# finishes it before writing its own temporaries, so failing partway can't cost it its blob half.
func test_next_save_finishes_a_committed_save_before_writing() -> void:
    var new_edit := _dig_center() + Vector3(40, 0, 0)
    _write_pair()
    _write_pending_pair(new_edit)
    DirAccess.rename_absolute(SNAPSHOT + SavedWorld.TMP_SUFFIX, SNAPSHOT)
    var saving := ShortWriteSave.new(SNAPSHOT, EDITSTORE, EDITSTORE + SavedWorld.TMP_SUFFIX)

    assert_ne(saving.save(_world_stub(), _edited_manager()), "", "the new save fails")
    _assert_loads_as_the_new_save(_read(), new_edit)


func test_unfinishable_interrupted_save_is_refused_and_kept() -> void:
    _write_pending_pair(_dig_center() + Vector3(40, 0, 0))
    DirAccess.make_dir_absolute(ProjectSettings.globalize_path(EDITSTORE))
    var saved := _read()

    assert_string_contains(saved.refusal, "an interrupted save couldn't be finished")
    assert_true(saved.snapshot.is_empty(), "the snapshot half isn't applied")
    assert_false(saved.load_into(null, null), "nothing loads")
    assert_string_contains(saved.save(null, null), "not overwriting")
    assert_true(FileAccess.file_exists(EDITSTORE + SavedWorld.TMP_SUFFIX), "the blob half is kept")


func test_snapshot_without_a_save_id_is_refused() -> void:
    var file := FileAccess.open(SNAPSHOT, FileAccess.WRITE)
    file.store_string(var_to_str({"version": WorldSnapshot.VERSION, "player": {}, "voxels": []}))
    file.close()
    assert_eq(_edited_manager().save_to(EDITSTORE, SAVE_ID), OK)

    _assert_refused_and_kept(_read(), "world snapshot has no save id")


func test_blob_that_fails_to_load_blocks_the_snapshot_and_f5() -> void:
    var source := _world_stub()
    source.get_node("Player").tool_index = 5
    assert_eq(_read().save(source, _edited_manager()), "")
    var saved := _read()
    assert_eq(saved.refusal, "", "the pair vets")
    FileAccess.open(EDITSTORE, FileAccess.WRITE).store_32(0)

    var world := _world_stub()
    assert_false(saved.load_into(world, _fresh_manager()), "the load reports failure")
    assert_string_contains(saved.refusal, "terrain save didn't load")
    assert_eq(world.get_node("Player").tool_index, 2, "the snapshot isn't applied over fresh terrain")
    assert_string_contains(saved.save(world, _fresh_manager()), "not overwriting")
