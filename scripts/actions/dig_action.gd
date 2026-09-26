class_name DigAction
extends Action


enum Shape { SPHERE }

var position:  Vector3
var radius:    float
var shape:     int  # Shape enum

var store:     EditStore


func _init(
    p_position: Vector3,
    p_radius:   float,
    p_ctx:      ActionContext,
    p_shape:    int = Shape.SPHERE,
) -> void:
    position = p_position
    radius   = p_radius
    shape    = p_shape
    store    = p_ctx.store

func validate() -> bool:
    return true

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    if store == null:
        p.refused = true
        return p
    _stamp().flips(store).add_to(p)
    p.refused = p.is_empty()
    return p

func execute() -> void:
    if store == null:
        push_error("DigAction.execute(): no store")
        return

    # Write the very field the preview read; events are the cells whose sample point the write
    # actually flipped, measured across it. A carve repaints nothing.
    var lattice := _stamp()
    var before  := CellFlips.snapshot(store, lattice.cells())
    lattice.write(store, lattice.materials(store, -1, func(_c: Vector3) -> bool: return false, true))
    CellFlips.since(store, before).emit(store)

    # Box one cell wider than the dig sphere so the boundary-cell scan in
    # TerrainSupport sees newly-exposed neighbours just outside the sphere.
    var scan_origin := position - Vector3.ONE * (radius + 1.0)
    var scan_size   :=            Vector3.ONE * ((radius + 1.0) * 2.0)
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, scan_origin, scan_size))


# The field execute() writes — preview and events both read this brush.
func _stamp() -> SdfLattice:
    return SdfLattice.sphere_stamp(store, position, radius,
        VoxelConstants.STORE_OP_SUBTRACT, VoxelConstants.RENDER_BASE_CELL)
