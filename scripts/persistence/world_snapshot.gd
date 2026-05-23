class_name WorldSnapshot
extends RefCounted

const VERSION := 2


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
    if not (snap is Dictionary) or snap.get("version") != VERSION:
        return false
    apply(snap, world)
    return true


# --- encode ---

static func encode(world: Node) -> Dictionary:
    var integrity := world.get_node("StructuralIntegrity") as StructuralIntegrity
    var player    := world.get_node("Player") as CharacterBody3D
    return {
        "version": VERSION,
        "player":  _encode_player(player),
        "voxels":  _encode_voxels(integrity.terrain_support),
        "parts":   _encode_parts(integrity.part_support),
    }

static func _encode_player(player: CharacterBody3D) -> Dictionary:
    var head: Node3D    = player.get_node("Head")
    var bs:   BuildState = player.build_state
    return {
        "position":         player.global_position,
        "body_rotation_y":  player.rotation.y,
        "head_rotation_x":  head.rotation.x,
        "edit_mode_index":  player.edit_mode_index,
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
        out.append({
            "part_path":   data.part.resource_path,
            "material":    data.material.name,
            "placement_y": data.placement_y,
            "transform":   node.transform,
            "cells":       data.cells,
        })
    return out


# --- decode ---

static func apply(snap: Dictionary, world: Node) -> void:
    var integrity := world.get_node("StructuralIntegrity") as StructuralIntegrity
    var player    := world.get_node("Player") as CharacterBody3D
    _apply_voxels(integrity, snap.get("voxels", []))
    _apply_parts(world, integrity, snap.get("parts", []))
    _apply_player(player, snap.get("player", {}))

static func _apply_voxels(integrity: StructuralIntegrity, voxels: Array) -> void:
    for entry in voxels:
        var mat := Materials.from_name(StringName(entry["material"]))
        integrity.terrain_support.restore_voxel(entry["pos"], mat, entry["support"])

static func _apply_parts(world: Node, integrity: StructuralIntegrity, parts: Array) -> void:
    for entry in parts:
        var part: Part = load(entry["part_path"]) as Part
        if part == null:
            continue
        var material_name := StringName(entry["material"])
        var instance      := part.instantiate(material_name)
        instance.transform = entry["transform"]
        world.add_child(instance)
        integrity.register_part(
            instance,
            _retype_cells(entry["cells"]),
            Materials.from_name(material_name),
            entry["placement_y"],
            part,
        )

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
    player.edit_mode_index = data["edit_mode_index"]
    player.build_state.restore(
        data["build_part_path"],
        StringName(data["build_material"]),
        data["build_rotation"],
    )
