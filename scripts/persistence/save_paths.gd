class_name SavePaths
extends RefCounted

const SAVE_DIR       := "user://saves"
const SNAPSHOT_FILE  := "user://saves/world.snapshot"
const EDITSTORE_FILE := "user://saves/world.editstore" # the EditStore blob (terrain SDF persistence)


static func ensure_dir() -> void:
    var d := DirAccess.open("user://")
    if d != null and not d.dir_exists("saves"):
        d.make_dir_recursive("saves")

static func snapshot_exists() -> bool:
    return FileAccess.file_exists(SNAPSHOT_FILE)

static func editstore_exists() -> bool:
    return FileAccess.file_exists(EDITSTORE_FILE)
