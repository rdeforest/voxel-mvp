class_name Action
extends RefCounted

func validate() -> bool:
    push_warning("Action.validate() not implemented")
    return false

func execute() -> void:
    push_error("Action.execute() not implemented")
