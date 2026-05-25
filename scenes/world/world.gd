extends Node3D

@onready var _terrain:   VoxelLodTerrain     = $VoxelLodTerrain
@onready var _integrity: StructuralIntegrity = $StructuralIntegrity
@onready var _player:    CharacterBody3D     = $Player


func _enter_tree() -> void:
    SavePaths.ensure_dir()
    # If a reset is pending, detach the SQLite stream BEFORE the terrain
    # node enters the tree, so it never reads modified blocks from disk.
    # _enter_tree runs parent-first, so we get here before $VoxelLodTerrain
    # has run its own _enter_tree.
    if WorldSnapshot.reset_pending:
        $VoxelLodTerrain.stream = null

func _ready() -> void:
    var resetting := WorldSnapshot.reset_pending
    WorldSnapshot.reset_pending = false
    if not resetting and SavePaths.snapshot_exists():
        WorldSnapshot.load_into(SavePaths.SNAPSHOT_FILE, self)
    _register_console_commands()


# --- Console commands (Limbo) ---

func _register_console_commands() -> void:
    LimboConsole.register_command(_cmd_set,        "set",        "Set a terrain shader uniform (float). Usage: set <name> <value>")
    LimboConsole.register_command(_cmd_reset,      "reset",      "Delete the save (terrain DB + snapshot) and reload to a fresh world.")
    LimboConsole.register_command(_cmd_quiescent,  "quiescent",  "Print whether the world is quiescent (save-ready).")
    LimboConsole.register_command(_cmd_parts,      "parts",      "Print the number of tracked parts.")
    LimboConsole.register_command(_cmd_voxels,     "voxels",     "Print the number of tracked terrain voxels.")
    LimboConsole.register_command(_cmd_tp,         "tp",         "Teleport the player. Usage: tp <x> <y> <z>")
    LimboConsole.register_command(_cmd_quit,       "quit_game",  "Exit the game (separate from console's built-in quit).")

func _cmd_set(param: String, value: float) -> void:
    var mat := _terrain.material as ShaderMaterial
    if mat == null:
        LimboConsole.error("terrain has no ShaderMaterial")
        return
    mat.set_shader_parameter(param, value)
    LimboConsole.info("%s = %s" % [param, value])

func _cmd_reset() -> void:
    # Save files are left untouched on disk. Next scene-reload runs with
    # `reset_pending = true`, which detaches the terrain stream (procedural
    # terrain regenerates) and skips the snapshot load. F9 afterwards
    # reloads the saved state normally.
    WorldSnapshot.reset_pending = true
    LimboConsole.info("Resetting to defaults — saves left intact. F9 to restore.")
    get_tree().reload_current_scene.call_deferred()

func _cmd_quiescent() -> void:
    LimboConsole.info("quiescent: %s" % _integrity.is_quiescent())

func _cmd_parts() -> void:
    LimboConsole.info("parts: %d" % _integrity.part_support.part_registry.size())

func _cmd_voxels() -> void:
    LimboConsole.info("tracked voxels: %d" % _integrity.terrain_support.voxel_data.size())

func _cmd_tp(x: float, y: float, z: float) -> void:
    _player.global_position = Vector3(x, y, z)
    LimboConsole.info("teleported to %s" % _player.global_position)

func _cmd_quit() -> void:
    get_tree().quit()
