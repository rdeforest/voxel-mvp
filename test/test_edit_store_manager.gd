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
    var surface := SparseVoxelOctree.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
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
