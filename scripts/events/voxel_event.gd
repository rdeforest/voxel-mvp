class_name VoxelEvent
extends RefCounted

# Base class for all bus events. `cells` is the dispatch footprint —
# the bus looks up per-cell subscribers using these coordinates.

var grid_id: int
var cells:   Array[Vector3i] = []
