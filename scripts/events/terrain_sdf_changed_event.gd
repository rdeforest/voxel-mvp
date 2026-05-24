class_name TerrainSdfChangedEvent
extends VoxelEvent

const CHANNEL := &"terrain_sdf_changed"

var box_origin: Vector3
var box_size:   Vector3


func _init(p_grid_id: int, p_origin: Vector3, p_size: Vector3) -> void:
    grid_id    = p_grid_id
    box_origin = p_origin
    box_size   = p_size
    VoxelUtils.for_each_in_bounding_box(p_origin, p_size, func(pos: Vector3i) -> void:
        cells.append(pos))
