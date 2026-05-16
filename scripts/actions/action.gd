class_name Action
extends RefCounted

func validate() -> bool:
    return true

func execute() -> void:
    push_error("Action.execute() not implemented")
