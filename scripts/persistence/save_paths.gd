class_name SavePaths
extends RefCounted

const SAVE_DIR      := "user://saves"
const TERRAIN_DB    := "user://saves/world.db"
const SNAPSHOT_FILE := "user://saves/world.snapshot"


static func ensure_dir() -> void:
    var d := DirAccess.open("user://")
    if d != null and not d.dir_exists("saves"):
        d.make_dir_recursive("saves")

static func snapshot_exists() -> bool:
    return FileAccess.file_exists(SNAPSHOT_FILE)
