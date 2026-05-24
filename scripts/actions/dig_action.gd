class_name DigAction
extends Action

const GRID_ID = 0

enum Shape { SPHERE }

var position:  Vector3
var radius:    float
var shape:     int  # Shape enum

var terrain:   VoxelLodTerrain


func _init(
    p_position:  Vector3,
    p_radius:    float,
    p_terrain:   VoxelLodTerrain,
    p_shape:     int = Shape.SPHERE,
) -> void:
    position = p_position
    radius   = p_radius
    shape    = p_shape
    terrain  = p_terrain

func validate() -> bool:
    return true

func execute() -> void:
    if terrain == null:
        push_error("DigAction.execute(): no terrain")
        return

    var voxel_tool := terrain.get_voxel_tool()
    voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
    voxel_tool.mode    = VoxelTool.MODE_REMOVE
    voxel_tool.do_sphere(position, radius)

    var origin     := position - Vector3.ONE *  radius
    var dimensions :=            Vector3.ONE * (radius * 2.0)

    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(pos: Vector3i) -> void:
            if VoxelUtils.is_in_sphere(Vector3(pos), position, radius):
                VoxelEventBus.emit(
                    VoxelRemovedEvent.CHANNEL,
                    VoxelRemovedEvent.new(GRID_ID, pos))
    )

    # Box one cell wider than the dig sphere so the boundary-cell scan in
    # TerrainSupport sees newly-exposed neighbours just outside the sphere.
    var scan_origin := position - Vector3.ONE * (radius + 1.0)
    var scan_size   :=            Vector3.ONE * ((radius + 1.0) * 2.0)
    VoxelEventBus.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(GRID_ID, scan_origin, scan_size))
