class_name WorldSnapshot
extends RefCounted

# V6: parts dissolved into the EditStore (imprinted voxels) — the snapshot no longer
# encodes Node3D parts or snap points. Parts now persist via the EditStore blob (their
# SDF) + the tracked-voxel array (their support). Older saves load with `parts` ignored.
# V7: HUD tool-window layout (id -> viewport fraction). Older saves load with windows at default.
const VERSION := 7

# Survives scene reloads (static var on a loaded script). Set by the `reset`
# console command and consumed by world.gd on the next _ready. When true: the saved
# EditStore blob and snapshot are skipped for that load (fresh procedural terrain), and
# both save files are left untouched on disk.
static var reset_pending: bool = false


# --- public API ---

static func save(path: String, world: Node) -> Error:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(var_to_str(encode(world)))
    return OK

static func load_into(path: String, world: Node) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    var snap = str_to_var(file.get_as_text())
    if not (snap is Dictionary):
        return false
    var v: int = snap.get("version", 0)
    # Forward-compat: newer-than-known schema → refuse.
    # Backward-compat: older snapshot → load what we can, missing keys
    # use defaults (e.g. V2 saves lack tunables; shader keeps its defaults).
    if v > VERSION:
        return false
    apply(snap, world)
    return true


# --- encode ---

static func encode(world: Node) -> Dictionary:
    var integrity := world.get_node("StructuralIntegrity") as StructuralIntegrity
    var player    := world.get_node("Player") as CharacterBody3D
    return {
        "version":  VERSION,
        "player":   _encode_player(player),
        "voxels":   _encode_voxels(integrity.terrain_support),
        "tunables": _encode_tunables(),
        "windows":  _encode_windows(world),
    }

# HUD tool-window layout: each "tool_window"-group node's id -> position as a viewport FRACTION
# (resolution-independent, so a save made fullscreen restores right in a small window and vice versa).
static func _encode_windows(world: Node) -> Dictionary:
    var out: Dictionary = {}
    for w in world.get_tree().get_nodes_in_group("tool_window"):
        if w.window_id != "":
            out[w.window_id] = w.get_fraction()
    return out

static func _terrain_material() -> ShaderMaterial:
    return load(VoxelConstants.TERRAIN_MATERIAL_PATH) as ShaderMaterial   # the shared cached instance

static func _encode_tunables() -> Dictionary:
    var mat := _terrain_material()
    if mat == null:
        return {}
    var out: Dictionary = {}
    for prop in mat.get_property_list():
        var name: String = prop.name
        if not name.begins_with("shader_parameter/"):
            continue
        var uniform := name.substr("shader_parameter/".length())
        out[uniform] = mat.get_shader_parameter(uniform)
    return out

static func _encode_player(player: CharacterBody3D) -> Dictionary:
    var head: Node3D    = player.get_node("Head")
    var bs:   BuildState = player.build_state
    return {
        "position":         player.global_position,
        "body_rotation_y":  player.rotation.y,
        "head_rotation_x":  head.rotation.x,
        "tool_index":       player.tool_index,
        "activity_indices": player._activity_indices.duplicate(),
        "build_part_path":  bs.current_part().resource_path,
        "build_material":   String(bs.current_material()),
        "build_rotation":   bs.rotation,
    }

static func _encode_voxels(ts: TerrainSupport) -> Array:
    var out: Array = []
    for pos in ts.voxel_data:
        var rec: VoxelRecord = ts.voxel_data[pos]
        out.append({
            "pos":      pos,
            "material": rec.material.name,
            "support":  rec.support,
        })
    return out


# --- decode ---

static func apply(snap: Dictionary, world: Node) -> void:
    var integrity := world.get_node("StructuralIntegrity") as StructuralIntegrity
    var player    := world.get_node("Player") as CharacterBody3D
    _apply_voxels(integrity, snap.get("voxels", []))
    _apply_player(player, snap.get("player", {}))
    _apply_tunables(snap.get("tunables", {}))
    _apply_windows(world, snap.get("windows", {}))

static func _apply_windows(world: Node, windows: Dictionary) -> void:
    if windows.is_empty():
        return
    for w in world.get_tree().get_nodes_in_group("tool_window"):
        if windows.has(w.window_id):
            w.set_fraction(windows[w.window_id])

static func _apply_tunables(tunables: Dictionary) -> void:
    if tunables.is_empty():
        return
    var mat := _terrain_material()
    if mat == null:
        return
    for uniform in tunables:
        mat.set_shader_parameter(uniform, tunables[uniform])

static func _apply_voxels(integrity: StructuralIntegrity, voxels: Array) -> void:
    for entry in voxels:
        var mat := Materials.from_name(StringName(entry["material"]))
        integrity.terrain_support.restore_voxel(entry["pos"], mat, entry["support"])

static func _apply_player(player: CharacterBody3D, data: Dictionary) -> void:
    if data.is_empty():
        return
    player.global_position = data["position"]
    player.rotation.y      = data["body_rotation_y"]
    var head: Node3D = player.get_node("Head")
    head.rotation.x  = data["head_rotation_x"]
    # tool_index + activity_indices replace the old V3 edit_mode_index.
    # Old saves without these keys: default to the None tool, activity 0.
    if data.has("tool_index"):
        player.tool_index = data["tool_index"]
    if data.has("activity_indices"):
        var raw: Array = data["activity_indices"]
        for i in mini(raw.size(), player._activity_indices.size()):
            player._activity_indices[i] = raw[i]
    player.build_state.restore(
        data["build_part_path"],
        StringName(data["build_material"]),
        data["build_rotation"],
    )
