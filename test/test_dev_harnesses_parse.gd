extends GutTest

# scripts/dev/ carries a .gdignore, so the editor never parses it and an API change can leave a
# harness broken until someone next runs it. Compiling each one here makes that a GUT failure.
# Loading a script runs its static initializers, so harnesses must keep static init side-effect-free.

const DEV_DIR := "res://scripts/dev/"


func test_every_dev_harness_compiles() -> void:
    var paths := _scripts_under(DEV_DIR)

    assert_gt(paths.size(), 0, "found no harnesses under %s" % DEV_DIR)

    for path in paths:
        var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript

        assert_not_null(script, "%s failed to load" % path)

        if script:
            assert_true(script.can_instantiate(), "%s failed to compile" % path)


func _scripts_under(dir_path: String) -> PackedStringArray:
    var found := PackedStringArray()

    for file in DirAccess.get_files_at(dir_path):
        if file.get_extension() == "gd":
            found.append(dir_path.path_join(file))

    for sub in DirAccess.get_directories_at(dir_path):
        found.append_array(_scripts_under(dir_path.path_join(sub)))

    return found
