class_name DigAction
extends Action


enum Shape { SPHERE }

var position:  Vector3
var radius:    float
var shape:     int  # Shape enum

var store:     EditStore


func _init(
    p_position:  Vector3,
    p_radius:    float,
    p_store:     EditStore,
    p_shape:     int = Shape.SPHERE,
) -> void:
    position = p_position
    radius   = p_radius
    shape    = p_shape
    store    = p_store

func validate() -> bool:
    return true

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    if store == null:
        p.refused = true
        return p
    var origin     := position - Vector3.ONE *  radius
    var dimensions :=            Vector3.ONE * (radius * 2.0)
    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(cell: Vector3i) -> void:
            if not VoxelUtils.is_in_sphere(Vector3(cell), position, radius):
                return
            if store.sample(Vector3(cell)) < VoxelConstants.SDF_SOLID_THRESHOLD:
                p.air.append(cell)
    )
    p.refused = p.is_empty()
    return p

func execute() -> void:
    if store == null:
        push_error("DigAction.execute(): no store")
        return

    store.stamp_sphere(position, radius, VoxelConstants.STORE_OP_SUBTRACT, 0, 1.0)

    var origin     := position - Vector3.ONE *  radius
    var dimensions :=            Vector3.ONE * (radius * 2.0)

    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(pos: Vector3i) -> void:
            if VoxelUtils.is_in_sphere(Vector3(pos), position, radius):
                VoxelEventBusSingleton.emit(
                    VoxelRemovedEvent.CHANNEL,
                    VoxelRemovedEvent.new(VoxelConstants.GRID_ID, pos))
    )

    # Box one cell wider than the dig sphere so the boundary-cell scan in
    # TerrainSupport sees newly-exposed neighbours just outside the sphere.
    var scan_origin := position - Vector3.ONE * (radius + 1.0)
    var scan_size   :=            Vector3.ONE * ((radius + 1.0) * 2.0)
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, scan_origin, scan_size))
