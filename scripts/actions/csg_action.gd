class_name CsgAction
extends AdditiveAction

# Stamps an analytic CSG primitive (box / cylinder / sphere) into the terrain SDF
# so the zero-crossing is the exact mathematical surface — a known field to audit
# the Dual Contouring mesh against. The shape's signed distance (CsgSdf, negative
# inside) is combined with the existing terrain per cell:
#   ADD      (union)        new = min(existing,  d)
#   SUBTRACT (difference)   new = max(existing, -d)
# evaluated at the integer lattice points the mesher reads, over the shape's
# rotated AABB plus a margin so the surface band is written on every side.

var shape:    CsgShape      # active primitive: owns its dims, SDF, and local AABB
var xform:    Transform3D   # shape local -> world (rotation basis + placement origin)
var op:       int           # CsgState.Op

var store:    EditStore

# Cached work: [[Vector3i cell, float new_sdf, bool was_solid, bool now_solid], ...]
var _work: Array         = []
var _work_computed: bool = false


func _init(
    p_shape:    CsgShape,
    p_xform:    Transform3D,
    p_op:       int,
    p_material: StringName,
    p_ctx:      ActionContext,
) -> void:
    shape         = p_shape
    xform         = p_xform
    op            = p_op
    material_name = p_material
    store         = p_ctx.store
    player        = p_ctx.player


func validate() -> bool:
    _ensure_work()
    if _work.is_empty():
        return false
    return not _endangers()


func preview() -> ActionPreview:
    var p := ActionPreview.new()
    _ensure_work()
    for entry in _work:
        if entry[3]:                      # now solid
            p.solid.append(entry[0])
        elif entry[2]:                    # was solid, now air
            p.air.append(entry[0])
    p.refused = _work.is_empty() or _endangers()
    return p


func execute() -> void:
    if store == null:
        push_error("CsgAction.execute(): no store")
        return
    _ensure_work()
    if op == CsgState.Op.ADD:
        _freeze_bodies_in_volume()
    VoxelImprint.apply(store, _work, material_name, shape, xform, op)


# --- Internals ---

func _world_box() -> AABB:
    return VoxelImprint.world_box(shape, xform)


func _ensure_work() -> void:
    if _work_computed or store == null:
        return
    _work          = VoxelImprint.compute(store, shape, xform, op)
    _work_computed = true


# Refuse if the stamp would bury the player (new solid in their capsule) or cut the
# ground out from under their feet (new air in the support box). Boxes: PlayerSafeAction.
func _endangers() -> bool:
    for entry in _work:
        var was_solid: bool = entry[2]
        var now_solid: bool = entry[3]
        if now_solid and not was_solid and buries(entry[0]):
            return true
        if was_solid and not now_solid and drops(entry[0]):
            return true
    return false


# Freeze any RigidBody3D inside the stamp volume before the SDF mutation lands,
# so physics doesn't squirt it sideways from the overlap on the next tick (same
# guard FillAction uses; the buried-body classifier reintegrates it afterwards).
func _freeze_bodies_in_volume() -> void:
    if player == null:
        return
    var box   := _world_box()
    var shape3 := BoxShape3D.new()
    shape3.size = box.size
    PhysicsUtils.freeze_bodies_in(
        player.get_world_3d().direct_space_state, shape3, Transform3D(Basis(), box.position + box.size * 0.5))
