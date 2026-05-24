class_name RegionCollapsingEvent
extends VoxelEvent

const CHANNEL := &"region_collapsing"


func _init(p_grid_id: int, p_cells: Array[Vector3i]) -> void:
    grid_id = p_grid_id
    cells   = p_cells
