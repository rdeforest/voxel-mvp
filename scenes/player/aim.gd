class_name Aim
extends RefCounted

# What the current activity is targeting this frame. `position`/`normal` are the
# world point to act on; `hit` is true for a real surface hit, false for a
# synthesized air point (Build placing into empty space at a fixed distance).

var position: Vector3
var normal:   Vector3
var hit:      bool


func _init(p_position: Vector3, p_normal: Vector3, p_hit: bool) -> void:
    position = p_position
    normal   = p_normal
    hit      = p_hit
