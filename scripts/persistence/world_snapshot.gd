class_name WorldSnapshot
extends RefCounted

# One save format until there are play testers: a snapshot of any other version is refused, not
# migrated. V8 added the save id shared with the EditStore blob (SavedWorld pairs the two); V9 the
# PartIndex, so part identity survives a reload.
const VERSION := 9

# Survives scene reloads (static var on a loaded script). Set by the `reset`
# console command and consumed by world.gd on the next _ready. When true: the saved
# EditStore blob and snapshot are skipped for that load (fresh procedural terrain), and
# both save files are left untouched on disk.
static var reset_pending: bool = false


# --- public API ---

# `world` is the World scene root: what's saved is read from its StructuralIntegrity and Player
# children and its part_index().

# `save_id` ties this snapshot to the EditStore blob written beside it.
static func save(path: String, world: Node, save_id: int) -> Error:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()

    return OK if file.store_string(var_to_str(encode(world, save_id))) else ERR_FILE_CANT_WRITE

# The parsed snapshot at `path`; empty when it can't be opened or isn't a snapshot.
static func read(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var snap = str_to_var(file.get_as_text())
    return snap if snap is Dictionary else {}

# Why this build won't apply `snap`, or "" when it will.
static func refusal(snap: Dictionary) -> String:
    if snap.is_empty():
        return "world snapshot is unreadable"

    var v: int = snap.get("version", 0)
    if v != VERSION:
        return "world snapshot is format v%d; this build reads only v%d" % [v, VERSION]
    if not (snap.get("save_id") is int):
        return "world snapshot has no save id"
    if not (snap.get("parts") is PackedByteArray):
        return "world snapshot has no part index"
    return PartIndex.refusal(bytes_to_var(snap["parts"]))


# --- encode ---

static func encode(world: Node, save_id: int) -> Dictionary:
    var integrity := world.get_node("StructuralIntegrity") as StructuralIntegrity
    var player    := world.get_node("Player") as CharacterBody3D
    return {
        "version":  VERSION,
        "save_id":  save_id,
        "player":   _encode_player(player),
        "voxels":   _encode_voxels(integrity.terrain_support),
        "parts":    _encode_parts(world.part_index()),
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

# Stored as bytes: var_to_str/str_to_var don't round-trip doubles exactly (about a third come back
# an ulp off; scripts/dev/probe_var_to_str_precision.gd), and a part's transform is identity, not a
# display value.
static func _encode_parts(index: PartIndex) -> PackedByteArray:
    return var_to_bytes(index.encode())

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
    _apply_parts(world.part_index(), snap["parts"])
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

static func _apply_parts(index: PartIndex, parts: PackedByteArray) -> void:
    index.restore(bytes_to_var(parts))

static func _apply_player(player: CharacterBody3D, data: Dictionary) -> void:
    if data.is_empty():
        return
    player.global_position = data["position"]
    player.rotation.y      = data["body_rotation_y"]
    var head: Node3D = player.get_node("Head")
    head.rotation.x  = data["head_rotation_x"]
    player.tool_index = data["tool_index"]

    var raw: Array = data["activity_indices"]
    for i in mini(raw.size(), player._activity_indices.size()):
        player._activity_indices[i] = raw[i]

    player.build_state.restore(
        data["build_part_path"],
        StringName(data["build_material"]),
        data["build_rotation"],
    )
