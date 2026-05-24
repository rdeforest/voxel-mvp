class_name VoxelRemovedEvent
extends VoxelEvent

const CHANNEL := &"voxel_removed"

var pos: Vector3i


func _init(p_grid_id: int, p_pos: Vector3i) -> void:
    grid_id = p_grid_id
    pos     = p_pos
    cells   = [p_pos]
