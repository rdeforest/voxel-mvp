class_name VoxelSupportChangedEvent
extends VoxelEvent

const CHANNEL := &"voxel_support_changed"

var pos:         Vector3i
var old_support: float
var new_support: float


func _init(p_grid_id: int, p_pos: Vector3i, p_old: float, p_new: float) -> void:
    grid_id     = p_grid_id
    pos         = p_pos
    old_support = p_old
    new_support = p_new
    cells       = [p_pos]
