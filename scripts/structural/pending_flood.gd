class_name PendingFlood
extends RefCounted

var voxels:   Array[Vector3i] = []
var frontier: Array[Vector3i]
var visited:  Dictionary      = {}

func _init(seed_pos: Vector3i) -> void:
    frontier = [seed_pos]
    visited  = { seed_pos: true }
