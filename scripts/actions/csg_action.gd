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

# Cached prediction from the field the stamp writes (VoxelImprint.lattice): whether it changes
# the store at all (nothing = refuse), which cells it flips (the ghost), and the field itself (the
# player-safety test). A brush thinner than a cell can write real geometry that flips no cell
# centre; that is placed — unless that geometry lands in the player.
var _writes: bool        = false
var _lattice: SdfLattice = null            # the field the stamp writes (player safety)
var _work: CellFlips     = CellFlips.new()
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
    source        = p_ctx.source


func validate() -> bool:
    _ensure_work()
    if not _writes:
        return false
    return not endangered_by(_lattice, store)


func preview() -> ActionPreview:
    var p := ActionPreview.new()
    _ensure_work()
    _work.add_to(p)
    p.refused = not _writes or endangered_by(_lattice, store)
    return p


func execute() -> void:
    if store == null:
        push_error("CsgAction.execute(): no store")
        return
    _ensure_work()
    if op == CsgState.Op.ADD:
        _freeze_bodies_in_volume()
    VoxelImprint.apply(store, source, material_name, shape, xform, op)


# --- Internals ---

func _world_box() -> AABB:
    return VoxelImprint.world_box(shape, xform)


func _ensure_work() -> void:
    if _work_computed or store == null:
        return
    _lattice       = VoxelImprint.lattice(store, shape, xform, op)
    _writes        = _lattice.writes
    _work          = _lattice.flips(store)
    _work_computed = true


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
