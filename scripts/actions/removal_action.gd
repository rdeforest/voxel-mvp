class_name RemovalAction
extends Action

var target_node: Node3D
var integrity:   StructuralIntegrity

func _init(p_node: Node3D, p_integrity: StructuralIntegrity) -> void:
    target_node = p_node
    integrity   = p_integrity

func validate() -> bool:
    return integrity.part_registry.has(target_node)

func execute() -> void:
    integrity.remove_part(target_node)
    target_node.queue_free()
