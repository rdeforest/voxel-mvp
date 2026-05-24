class_name PartSupportChangedEvent
extends VoxelEvent

const CHANNEL := &"part_support_changed"

var node:        Node3D
var old_support: float
var new_support: float


func _init(
        p_grid_id: int,
        p_node:    Node3D,
        p_cells:   Array[Vector3i],
        p_old:     float,
        p_new:     float) -> void:
    grid_id     = p_grid_id
    node        = p_node
    cells       = p_cells
    old_support = p_old
    new_support = p_new
