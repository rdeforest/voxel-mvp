class_name Action
extends RefCounted

var source: EditSource.Kind   # who execute()'s matter-changed event credits (ActionContext.source)

func validate() -> bool:
    push_warning("Action.validate() not implemented")
    return false

func execute() -> void:
    push_error("Action.execute() not implemented")

# Returns the cells this action would change at the current configuration.
# Default: empty preview. Subclasses override.
func preview() -> ActionPreview:
    return ActionPreview.new()

# The resolved constructor arguments, as plain data (StepFields shapes), for StepRegistry to write
# as a step and rebuild from. Only what the action was built with: the player's position the
# safety checks read is the step stream's (player_at), not the action's. Each subclass also has a
# static from_step(fields: StepFields, ctx: ActionContext) -> Action, its inverse.
func to_step() -> Dictionary:
    push_error("Action.to_step() not implemented")
    return {}
