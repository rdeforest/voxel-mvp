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

func _exit_tree() -> void:
    # Drop our console commands before this world is freed (scene reload / quit)
    # so LimboConsole never holds a callable bound to a freed object.
    _unregister_console_commands()


# --- Console commands (Limbo) ---
#
# The LimboConsole autoload outlives this scene. On reload (F9 / reset) the old
# world is freed; a command left registered would point at a freed object and
# crash LimboConsole's introspection (get_method_list on a null value). So we
# register on _ready and unregister on _exit_tree, keeping bindings live. One
# command list feeds both so the names can't drift.
func _console_commands() -> Array:
    return [
        [_cmd_set,       "set",       "Set a terrain shader uniform (float). Usage: set <name> <value>"],
        [_cmd_get,       "get",       "List terrain shader uniforms matching a glob (default *). Usage: get [pattern]"],
        [_cmd_vdebug,    "vdebug",    "Toggle a VoxelLodTerrain debug overlay. Usage: vdebug [flag]; no arg lists flags."],
        [_cmd_reset,     "reset",     "Delete the save (terrain DB + snapshot) and reload to a fresh world."],
        [_cmd_quiescent, "quiescent", "Print whether the world is quiescent (save-ready)."],
        [_cmd_parts,     "parts",     "Print the number of tracked parts."],
        [_cmd_voxels,    "voxels",    "Print the number of tracked terrain voxels."],
        [_cmd_tp,        "tp",        "Teleport the player. Usage: tp <x> <y> <z>"],
        [_cmd_quit,      "quit_game", "Exit the game (separate from console's built-in quit)."],
    ]

func _register_console_commands() -> void:
    for c in _console_commands():
        if not LimboConsole.has_command(c[1]):
            LimboConsole.register_command(c[0], c[1], c[2])

func _unregister_console_commands() -> void:
    if not is_instance_valid(LimboConsole):
        return
    for c in _console_commands():
        if LimboConsole.has_command(c[1]):
            LimboConsole.unregister_command(c[1])

func _cmd_set(param: String, value: float) -> void:
    var mat := _terrain.material as ShaderMaterial
    if mat == null:
        LimboConsole.error("terrain has no ShaderMaterial")
        return
    mat.set_shader_parameter(param, value)
    _push_terrain_material(mat)
    LimboConsole.info("%s = %s" % [param, value])

# VoxelLodTerrain renders each mesh block with its own pooled COPY of the
# material (so blocks can carry per-block LOD uniforms); _terrain.material is
# only the template. Changing a uniform on the template doesn't touch the live
# copies. Re-assigning the material re-pools every block from the template —
# godot_voxel preserves only its own per-block uniforms across the copy, so our
# custom uniforms refresh from the template. The null hop defeats set_material's
# identity early-out (it ignores assignment of the same instance).
func _push_terrain_material(mat: ShaderMaterial) -> void:
    _terrain.material = null
    _terrain.material = mat

# VoxelLodTerrain.DebugDrawFlag indices (see voxel_lod_terrain.h). active_mesh_blocks
# draws a box per visually-active mesh block, coloured by LOD — overlapping boxes
# of different sizes at one spot mean several LODs are active there.
const _VDEBUG_FLAGS := {
    "octree_nodes":       0,
    "octree_bounds":      1,
    "mesh_updates":       2,
    "edit_boxes":         3,
    "volume_bounds":      4,
    "edited_blocks":      5,
    "modifier_bounds":    6,
    "active_mesh_blocks": 7,
    "viewer_clipboxes":   8,
    "loaded_blocks":      9,
    "active_blocks":      10,
    "voxel_metadata":     11,
}

func _cmd_vdebug(flag_name: String = "") -> void:
    if not _VDEBUG_FLAGS.has(flag_name):
        LimboConsole.info("flags: " + ", ".join(PackedStringArray(_VDEBUG_FLAGS.keys())))
        return
    var idx: int = _VDEBUG_FLAGS[flag_name]
    var enabled := not _terrain.debug_get_draw_flag(idx)
    _terrain.debug_set_draw_flag(idx, enabled)
    # Per-flag flags draw nothing unless the master debug renderer is enabled.
    # Keep it on while any flag is set, off when none remain.
    var any := false
    for flag in _VDEBUG_FLAGS:
        if _terrain.debug_get_draw_flag(_VDEBUG_FLAGS[flag]):
            any = true
            break
    _terrain.debug_set_draw_enabled(any)
    LimboConsole.info("vdebug %s = %s" % [flag_name, enabled])

func _cmd_get(pattern: String = "*") -> void:
    var mat := _terrain.material as ShaderMaterial
    if mat == null:
        LimboConsole.error("terrain has no ShaderMaterial")
        return
    var found := 0
    for prop in mat.get_property_list():
        var pname: String = prop.name
        if not pname.begins_with("shader_parameter/"):
            continue
        var uniform := pname.substr("shader_parameter/".length())
        if not uniform.matchn(pattern):
            continue
        # get_shader_parameter returns the override, or null when the uniform
        # is at its shader default (not yet set on this material).
        var v: Variant = mat.get_shader_parameter(uniform)
        LimboConsole.info("%s = %s" % [uniform, "(default)" if v == null else v])
        found += 1
    if found == 0:
        LimboConsole.info("no shader uniforms match '%s'" % pattern)

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
