class_name PartRemovedEvent
extends VoxelEvent

const CHANNEL := &"part_removed"

var node: Node3D


func _init(p_grid_id: int, p_node: Node3D) -> void:
    grid_id = p_grid_id
    node    = p_node
