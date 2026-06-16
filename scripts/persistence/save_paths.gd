class_name SavePaths
extends RefCounted

const SAVE_DIR       := "user://saves"
const SNAPSHOT_FILE  := SAVE_DIR + "/world.snapshot"
const EDITSTORE_FILE := SAVE_DIR + "/world.editstore" # the EditStore blob (terrain SDF persistence)


static func ensure_dir() -> void:
    var d := DirAccess.open("user://")
    var leaf := SAVE_DIR.trim_prefix("user://")
    if d != null and not d.dir_exists(leaf):
        d.make_dir_recursive(leaf)

static func snapshot_exists() -> bool:
    return FileAccess.file_exists(SNAPSHOT_FILE)

static func editstore_exists() -> bool:
    return FileAccess.file_exists(EDITSTORE_FILE)
