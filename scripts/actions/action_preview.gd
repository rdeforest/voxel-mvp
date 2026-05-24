class_name ActionPreview
extends RefCounted

# Per-cell intent for the preview renderer:
#   air   — cell currently solid, will become air after the action.
#   solid — cell currently air, will become solid after the action.
#   part  — cell will be claimed by a Part (Construction mode).
#
# An action can populate multiple lists (Flatten cuts AND fills in one
# gesture). `refused` is true when validate() would reject the action;
# the renderer dims the visuals to communicate that clicking won't do
# anything.

var air:     Array[Vector3i] = []
var solid:   Array[Vector3i] = []
var part:    Array[Vector3i] = []
var refused: bool            = false


func is_empty() -> bool:
    return air.is_empty() and solid.is_empty() and part.is_empty()
