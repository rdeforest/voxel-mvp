class_name PartAddedEvent
extends VoxelEvent

const CHANNEL := &"part_added"

var node:        Node3D
var material:    Materials
var placement_y: float
var part:        Part


func _init(
        p_grid_id:     int,
        p_node:        Node3D,
        p_cells:       Array[Vector3i],
        p_material:    Materials,
        p_placement_y: float,
        p_part:        Part) -> void:
    grid_id     = p_grid_id
    node        = p_node
    cells       = p_cells
    material    = p_material
    placement_y = p_placement_y
    part        = p_part
