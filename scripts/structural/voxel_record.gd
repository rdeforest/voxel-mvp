class_name VoxelRecord
extends RefCounted

var support:  float = 0.0
var material: Materials
var dirty:    bool  = true

func _init(p_material: Materials) -> void:
    material = p_material
