class_name FillAction
extends AdditiveAction

enum Shape { SPHERE }

var position:  Vector3
var radius:    float
var shape:     int  # Shape enum
var store:     EditStore

var _stamp_cache: SdfLattice = null


func _init(
    p_position: Vector3,
    p_radius:   float,
    p_ctx:      ActionContext,
    p_material: StringName = &"Stone",
    p_shape:    int = Shape.SPHERE,
) -> void:
    position      = p_position
    radius        = p_radius
    shape         = p_shape
    store         = p_ctx.store
    player        = p_ctx.player
    material_name = p_material

func validate() -> bool:
    if store == null:
        return false
    return not endangered_by(_stamp(), store)

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    if store == null:
        return p
    _stamp().flips(store).add_to(p)
    return p

func execute() -> void:
    if store == null:
        push_error("FillAction.execute(): no store")
        return

    # Freeze any falling bodies inside the fill volume *before* the SDF mutation lands,
    # so physics doesn't squirt them sideways on the next tick. The buried-body
    # classifier integrates them into the SDF the moment they're fully covered.
    _freeze_bodies_in_volume()

    # Write the very field the preview read; events are the cells whose sample point the write
    # actually flipped, measured across it. What the sphere makes solid takes the fill material.
    var lattice := _stamp()
    var before  := CellFlips.snapshot(store, lattice.cells())
    lattice.write(store, lattice.materials(store, MaterialPalette.index_of(material_name),
        func(c: Vector3) -> bool: return c.distance_to(position) < radius, true))
    CellFlips.since(store, before).emit(store)

    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, lattice.region_lo, lattice.region_hi - lattice.region_lo))


# The field execute() writes — validate, preview and events all read this brush. Stamped once, so
# the cache is a snapshot of the store: safe only because every caller builds a fresh action and
# runs validate/preview/execute with no other write in between (player.gd, the preview renderer).
func _stamp() -> SdfLattice:
    if _stamp_cache == null:
        _stamp_cache = SdfLattice.sphere_stamp(store, position, radius,
            VoxelConstants.STORE_OP_UNION, VoxelConstants.RENDER_BASE_CELL)
    return _stamp_cache


func _freeze_bodies_in_volume() -> void:
    if player == null:
        return
    var sphere := SphereShape3D.new()
    sphere.radius = radius
    PhysicsUtils.freeze_bodies_in(
        player.get_world_3d().direct_space_state, sphere, Transform3D(Basis(), position))
