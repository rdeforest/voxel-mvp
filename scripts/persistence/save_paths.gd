class_name SavePaths
extends RefCounted

# Where F5 / F9's save pair lives. `root` moves only in GUT, which points it into each run's own
# directory (test/support/run_paths.gd) so no test touches the player's saves.

const DEFAULT_ROOT   := "user://saves"
const SNAPSHOT_NAME  := "world.snapshot"
const EDITSTORE_NAME := "world.editstore" # the EditStore blob (terrain SDF persistence)

static var root := DEFAULT_ROOT


static func ensure_dir() -> void:
    DirAccess.make_dir_recursive_absolute(root)

static func snapshot_exists() -> bool:
    return FileAccess.file_exists("%s/%s" % [root, SNAPSHOT_NAME])
