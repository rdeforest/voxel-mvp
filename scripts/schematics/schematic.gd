class_name Schematic
extends Resource

# Empty footprint means "compute from mesh bounds at placement time."
@export var footprint:   Array[Vector3i] = []

# Hand-authored snap point positions in local space. UI deferred to v0.1.
@export var snap_points: Array[Vector3]  = []
