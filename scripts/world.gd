extends Node3D

func _enter_tree() -> void:
    SavePaths.ensure_dir()

func _ready() -> void:
    if SavePaths.snapshot_exists():
        WorldSnapshot.load_into(SavePaths.SNAPSHOT_FILE, self)
