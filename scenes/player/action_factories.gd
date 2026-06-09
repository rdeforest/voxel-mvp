class_name ActionFactories
extends RefCounted

const EDIT_RADIUS := 3.0

# Magnet reach: a placement snap point within this distance of an existing world
# snap point pulls the part into coincidence.
const SNAP_RADIUS := 0.75

var _player:      CharacterBody3D
var _terrain:     VoxelLodTerrain
var _integrity:   StructuralIntegrity
var _camera:      Camera3D
var _raycast:     RayCast3D
var _build_state: BuildState
var _csg_state:   CsgState
var _pbd:         PbdStructure   # resolved lazily — created by world after the player


func _init(
    player:      CharacterBody3D,
    terrain:     VoxelLodTerrain,
    integrity:   StructuralIntegrity,
    camera:      Camera3D,
    raycast:     RayCast3D,
    build_state: BuildState,
    csg_state:   CsgState,
) -> void:
    _player      = player
    _terrain     = terrain
    _integrity   = integrity
    _camera      = camera
    _raycast     = raycast
    _build_state = build_state
    _csg_state   = csg_state


# --- Factories (one per EditMode) ---

func make_probe(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    return ProbeAction.new(hit_pos, hit_normal, _build_state.placement_offset, _terrain, _integrity, _pbd_structure())

# PbdStructure is added to the world after the player's _ready, so it can't be
# captured at construction — resolve it on first use and cache.
func _pbd_structure() -> PbdStructure:
    if _pbd == null:
        _pbd = _player.get_parent().get_node_or_null(^"PbdStructure")
    return _pbd

func make_dig(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var center := hit_pos - hit_normal * (EDIT_RADIUS * 0.5)
    return DigAction.new(center, EDIT_RADIUS, _terrain)

func make_fill(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var center := hit_pos + hit_normal * (EDIT_RADIUS * 0.5)
    return FillAction.new(center, EDIT_RADIUS, _terrain, _player, _build_state.current_material())

func make_flatten(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var flatten_normal := get_flatten_normal()
    if flatten_normal == Vector3.ZERO:
        flatten_normal = hit_normal
    return FlattenAction.new(hit_pos, flatten_normal, EDIT_RADIUS, _terrain, _player)

func make_raise(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    return RaiseAction.new(hit_pos, EDIT_RADIUS, _terrain, _player)

func make_lower(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    return LowerAction.new(hit_pos, EDIT_RADIUS, _terrain, _player)

func make_fill_voxel(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var pos := hit_pos + hit_normal * 0.5     # nudge into the air cell
    var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
    return FillVoxelAction.new(cell, _terrain, _player, _build_state.current_material())

func make_empty_voxel(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var pos := hit_pos - hit_normal * 0.01    # nudge into the solid cell
    var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
    return EmptyVoxelAction.new(cell, _terrain)

func make_removal(_hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    var collider := _raycast.get_collider()
    if collider == null or not _integrity.has_part(collider):
        return null
    return RemovalAction.new(collider, _integrity)

func make_add_snap(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    var collider := _raycast.get_collider()
    if collider == null or not _integrity.has_part(collider):
        return null
    return AddSnapAction.new(collider, hit_pos, _proto_snap_points(collider), _integrity)

func make_remove_snap(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    var collider := _raycast.get_collider()
    if collider == null or not _integrity.has_part(collider):
        return null
    return RemoveSnapAction.new(collider, hit_pos, SnapPoints.PICK_RADIUS, _proto_snap_points(collider), _integrity)

func _proto_snap_points(node: Node3D) -> Array:
    var data := _integrity.get_part_data(node)
    return data.part.snap_points if data != null else []

# One factory for all three CSG shapes — the active shape lives in CsgState
# (synced from the selected activity). The primitive is centred at the hit point
# plus the shared placement offset and rotated by the CSG rotation basis.
func make_csg(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    var origin := csg_placement_pos(hit_pos)
    var xform  := Transform3D(_csg_state.rotation_basis(), origin)
    return CsgAction.new(
        _csg_state.active_shape(),
        xform,
        _csg_state.op,
        _csg_state.current_material(),
        _terrain,
        _player,
    )

# Shared by make_csg and the ghost preview so the stamp and the ghost agree.
func csg_placement_pos(hit_pos: Vector3) -> Vector3:
    return hit_pos + _build_state.placement_offset


func make_construction(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    var placement_pos := build_placement_pos(hit_pos)
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


# --- Build placement (shared by make_construction and the ghost preview) ---

# Free placement (hit + accumulated offset), then pulled by the snap magnet
# toward nearby world snap points. Both the action and the preview ghost call
# this so they always agree on where the part lands.
func build_placement_pos(hit_pos: Vector3) -> Vector3:
    var base := hit_pos + _build_state.placement_offset
    return base + _snap_delta(base)

func _snap_delta(base_placement_pos: Vector3) -> Vector3:
    var part: Part = _build_state.current_part()
    if part.snap_points.is_empty():
        return Vector3.ZERO
    var xf    := part.world_transform(_build_state.rotation_basis(), base_placement_pos)
    var ghost := PackedVector3Array()
    for p in part.snap_points:
        ghost.append(xf * p)
    var world := SnapPoints.all_world(_integrity.part_support.part_registry)
    return SnapPoints.snap_delta(ghost, world, SNAP_RADIUS)


# --- Shared targeting helper (used by make_flatten and the Flatten preview) ---

func get_flatten_normal() -> Vector3:
    if Input.is_key_pressed(KEY_SHIFT):
        return Vector3.UP
    if Input.is_key_pressed(KEY_CTRL):
        var forward := _camera.global_transform.basis.z
        forward.y = 0.0
        return forward.normalized()
    return Vector3.ZERO  # sentinel meaning "use hit normal"
