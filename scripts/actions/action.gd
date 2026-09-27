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
