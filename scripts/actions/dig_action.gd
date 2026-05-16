class_name DigAction
extends Action

enum Shape { SPHERE }

var position: Vector3
var radius: float
var shape: int  # Shape enum

func _init(p_position: Vector3, p_radius: float, p_shape: int = Shape.SPHERE) -> void:
    position = p_position
    radius = p_radius
    shape = p_shape

func validate() -> bool:
    return true  # dig is always valid; refusal cases come later

func execute() -> void:
    # call the existing voxel-tool sphere remove logic
    # plus the integrity notification
    ...