class_name PendingCollapse
extends RefCounted

var voxels:    Array[Vector3i]
var voxel_set: Dictionary
var strained:  float = 0.0

func _init(p_voxels: Array[Vector3i]) -> void:
    voxels    = p_voxels
    voxel_set = {}
    for v in p_voxels:
        voxel_set[v] = true
