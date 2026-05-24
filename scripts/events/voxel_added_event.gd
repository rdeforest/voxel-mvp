class_name VoxelAddedEvent
extends VoxelEvent

const CHANNEL := &"voxel_added"

var pos:      Vector3i
var material: Materials


func _init(p_grid_id: int, p_pos: Vector3i, p_material: Materials) -> void:
    grid_id  = p_grid_id
    pos      = p_pos
    material = p_material
    cells    = [p_pos]
