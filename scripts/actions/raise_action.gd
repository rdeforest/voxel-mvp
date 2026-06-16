class_name RaiseAction
extends BellSculptAction

# Push the terrain surface up: subtract the bell from the SDF (boundary rises).


func _init(p_position: Vector3, p_radius: float, p_ctx: ActionContext) -> void:
    super(p_position, p_radius, p_ctx, -1.0)
