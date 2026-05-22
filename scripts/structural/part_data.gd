class_name PartData
extends RefCounted

var cells:       Array[Vector3i]
var material:    Materials
var placement_y: float
var support:     float = 0.0
var in_limbo:    bool  = false

func _init(p_cells: Array[Vector3i], p_mat: Materials, p_y: float) -> void:
    cells       = p_cells
    material    = p_mat
    placement_y = p_y
