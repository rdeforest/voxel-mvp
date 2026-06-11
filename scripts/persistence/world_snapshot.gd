class_name WorldSnapshot
extends RefCounted

const VERSION := 5

# Survives scene reloads (static var on a loaded script). Set by the `reset`
# console command and consumed by world.gd on the next _enter_tree/_ready
# cycle. When true: the SQLite terrain stream is detached for that load
# (procedural-only terrain), and the snapshot file is left untouched on disk.
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
        "parts":    _encode_parts(integrity.part_support),
        "tunables": _encode_tunables(),
    }

static func _terrain_material() -> ShaderMaterial:
    return load(DCTerrainManager.TERRAIN_MATERIAL_PATH) as ShaderMaterial   # the shared cached instance

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

static func _encode_parts(ps: PartSupport) -> Array:
    var out: Array = []
    for node in ps.part_registry:
        var data: PartData = ps.part_registry[node]
        var entry := {
            "part_path":   data.part.resource_path,
            "material":    data.material.name,
            "placement_y": data.placement_y,
            "transform":   node.transform,
            "cells":       data.cells,
        }
        # Only forked instances carry own points; unforked ones inherit live
        # from the prototype, so we persist nothing and let them re-resolve.
        if SnapPoints.has_own(node):
            entry["snap_points"] = SnapPoints.own_local(node)
        out.append(entry)
    return out


# --- decode ---

static func apply(snap: Dictionary, world: Node) -> void:
    var integrity := world.get_node("StructuralIntegrity") as StructuralIntegrity
    var player    := world.get_node("Player") as CharacterBody3D
    _apply_voxels(integrity, snap.get("voxels", []))
    _apply_parts(world, integrity, snap.get("parts", []))
    _apply_player(player, snap.get("player", {}))
    _apply_tunables(snap.get("tunables", {}))

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

static func _apply_parts(world: Node, _integrity: StructuralIntegrity, parts: Array) -> void:
    for entry in parts:
        var part: Part = load(entry["part_path"]) as Part
        if part == null:
            continue
        var material_name := StringName(entry["material"])
        var instance      := part.instantiate(material_name)
        instance.transform = entry["transform"]
        world.add_child(instance)
        # Restore the fork only for instances that had own points; others keep
        # inheriting from the prototype (no metadata key written).
        if entry.has("snap_points"):
            SnapPoints.set_own(instance, entry["snap_points"])
        VoxelEventBusSingleton.emit(
            PartAddedEvent.CHANNEL,
            PartAddedEvent.new(
                0,
                instance,
                _retype_cells(entry["cells"]),
                Materials.from_name(material_name),
                entry["placement_y"],
                part))

static func _retype_cells(raw: Array) -> Array[Vector3i]:
    var out: Array[Vector3i] = []
    for c in raw:
        out.append(c)
    return out

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
