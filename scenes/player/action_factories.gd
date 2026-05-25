class_name ActionFactories
extends RefCounted

const EDIT_RADIUS := 3.0

var _player:      CharacterBody3D
var _terrain:     VoxelLodTerrain
var _integrity:   StructuralIntegrity
var _camera:      Camera3D
var _raycast:     RayCast3D
var _build_state: BuildState


func _init(
    player:      CharacterBody3D,
    terrain:     VoxelLodTerrain,
    integrity:   StructuralIntegrity,
    camera:      Camera3D,
    raycast:     RayCast3D,
    build_state: BuildState,
) -> void:
    _player      = player
    _terrain     = terrain
    _integrity   = integrity
    _camera      = camera
    _raycast     = raycast
    _build_state = build_state


# --- Factories (one per EditMode) ---

func make_probe(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    return ProbeAction.new(hit_pos, hit_normal, _terrain, _integrity)

func make_dig(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var center := hit_pos - hit_normal * (EDIT_RADIUS * 0.5)
    return DigAction.new(center, EDIT_RADIUS, _terrain)

func make_fill(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var center := hit_pos + hit_normal * (EDIT_RADIUS * 0.5)
    return FillAction.new(center, EDIT_RADIUS, _terrain, _player)

func make_flatten(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var flatten_normal := get_flatten_normal()
    if flatten_normal == Vector3.ZERO:
        flatten_normal = hit_normal
    return FlattenAction.new(hit_pos, flatten_normal, EDIT_RADIUS, _terrain, _player)

func make_raise(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    return RaiseAction.new(hit_pos, EDIT_RADIUS, _terrain, _player)

func make_lower(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    return LowerAction.new(hit_pos, EDIT_RADIUS, _terrain)

func make_fill_voxel(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var pos := hit_pos + hit_normal * 0.5     # nudge into the air cell
    var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
    return FillVoxelAction.new(cell, _terrain, _player)

func make_empty_voxel(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var pos := hit_pos - hit_normal * 0.01    # nudge into the solid cell
    var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
    return EmptyVoxelAction.new(cell, _terrain)

func make_removal(_hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    var collider := _raycast.get_collider()
    if collider == null or not _integrity.has_part(collider):
        return null
    return RemovalAction.new(collider, _integrity)

func make_construction(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    var placement_pos := hit_pos + _build_state.placement_offset
    var anchor        := Vector3i(roundi(hit_pos.x), floori(hit_pos.y), roundi(hit_pos.z))
    return ConstructionAction.new(
        _build_state.current_part(),
        placement_pos,
        anchor,
        _build_state.rotation,
        _build_state.current_material(),
        _terrain,
        _integrity,
        _player,
    )


# --- Shared targeting helper (used by make_flatten and the Flatten preview) ---

func get_flatten_normal() -> Vector3:
    if Input.is_key_pressed(KEY_SHIFT):
        return Vector3.UP
    if Input.is_key_pressed(KEY_CTRL):
        var forward := _camera.global_transform.basis.z
        forward.y = 0.0
        return forward.normalized()
    return Vector3.ZERO  # sentinel meaning "use hit normal"
