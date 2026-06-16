class_name ActionFactories
extends RefCounted

const EDIT_RADIUS := 3.0

var _player:      CharacterBody3D
var _integrity:   StructuralIntegrity
var _camera:      Camera3D
var _build_state: BuildState
var _csg_state:   CsgState
var _pbd:         PbdStructure    # resolved lazily — created by world after the player
var _store_ref:   EditStore       # resolved lazily — created by world after the player
var _ctx_ref:     ActionContext   # built lazily; valid once both _store_ref and _pbd resolve


func _init(
    player:      CharacterBody3D,
    integrity:   StructuralIntegrity,
    camera:      Camera3D,
    build_state: BuildState,
    csg_state:   CsgState,
) -> void:
    _player      = player
    _integrity   = integrity
    _camera      = camera
    _build_state = build_state
    _csg_state   = csg_state


# The EditStore and PbdStructure are created in world._ready, after the player's
# _ready, so they can't be captured at construction — resolve on first use and
# cache. _action_ctx() builds the ActionContext once both are available.
func _store() -> EditStore:
    if _store_ref == null:
        _store_ref = _player.get_parent().edit_store_ref()
        _ctx_ref   = null   # invalidate so _action_ctx() rebuilds with the real store
    return _store_ref

func _pbd_structure() -> PbdStructure:
    if _pbd == null:
        _pbd     = _player.get_parent().get_node_or_null(^"PbdStructure")
        _ctx_ref = null   # invalidate so _action_ctx() rebuilds with the real pbd
    return _pbd

func _action_ctx() -> ActionContext:
    if _ctx_ref == null:
        _ctx_ref = ActionContext.new(_store(), _player, _integrity, _pbd_structure())
    return _ctx_ref


# --- Factories (one per EditMode) ---

func make_probe(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    return ProbeAction.new(hit_pos, hit_normal, _build_state.placement_offset, _action_ctx())

# The probe's read-out lines for an arbitrary target, tool-independent — the live
# probe HUD calls this every frame so scanning the scene works no matter which tool
# is selected.
func probe_report(hit_pos: Vector3, hit_normal: Vector3) -> PackedStringArray:
    return ProbeAction.new(hit_pos, hit_normal, _build_state.placement_offset, _action_ctx()).report()

func make_dig(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var center := hit_pos - hit_normal * (EDIT_RADIUS * 0.5)
    return DigAction.new(center, EDIT_RADIUS, _action_ctx())

func make_fill(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var center := hit_pos + hit_normal * (EDIT_RADIUS * 0.5)
    return FillAction.new(center, EDIT_RADIUS, _action_ctx(), _build_state.current_material())

func make_flatten(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var flatten_normal := get_flatten_normal()
    if flatten_normal == Vector3.ZERO:
        flatten_normal = hit_normal
    return FlattenAction.new(hit_pos, flatten_normal, EDIT_RADIUS, _action_ctx())

func make_raise(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    return RaiseAction.new(hit_pos, EDIT_RADIUS, _action_ctx())

func make_lower(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    return LowerAction.new(hit_pos, EDIT_RADIUS, _action_ctx())

func make_fill_voxel(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var pos  := hit_pos + hit_normal * 0.5
    var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
    return FillVoxelAction.new(cell, _action_ctx(), _build_state.current_material())

func make_empty_voxel(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var pos  := hit_pos - hit_normal * VoxelConstants.SURFACE_NUDGE
    var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
    return EmptyVoxelAction.new(cell, _action_ctx())

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
        _action_ctx(),
    )

# Shared by make_csg and the ghost preview so the stamp and the ghost agree.
func csg_placement_pos(hit_pos: Vector3) -> Vector3:
    return hit_pos + _build_state.placement_offset


func make_construction(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    return ConstructionAction.new(
        _build_state.current_part(),
        build_placement_pos(hit_pos),
        _build_state.rotation,
        _build_state.current_material(),
        _action_ctx(),
    )


# --- Build placement (shared by make_construction and the ghost preview) ---

# Free placement: the surface hit plus the accumulated offset. Both the action and
# the preview ghost call this so they always agree on where the part lands.
func build_placement_pos(hit_pos: Vector3) -> Vector3:
    return hit_pos + _build_state.placement_offset


# --- Shared targeting helper (used by make_flatten and the Flatten preview) ---

func get_flatten_normal() -> Vector3:
    if Input.is_key_pressed(KEY_SHIFT):
        return Vector3.UP
    if Input.is_key_pressed(KEY_CTRL):
        var forward := _camera.global_transform.basis.z
        forward.y   = 0.0
        return forward.normalized()
    return Vector3.ZERO  # sentinel meaning "use hit normal"
