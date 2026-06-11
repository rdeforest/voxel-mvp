class_name Schematic
extends Resource

# Empty footprint means "compute from mesh bounds at placement time."
@export var footprint:   Array[Vector3i] = []
