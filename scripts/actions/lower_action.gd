class_name LowerAction
extends BellSculptAction

# Push the terrain surface down: add the bell to the SDF (boundary drops). Takes the
# player (unlike before) so BellSculptAction can refuse to drop them through the floor.


func _init(p_position: Vector3, p_radius: float, p_ctx: ActionContext) -> void:
    super(p_position, p_radius, p_ctx, 1.0)
