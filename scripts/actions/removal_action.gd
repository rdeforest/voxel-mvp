class_name RemovalAction
extends Action

const GRID_ID = 0

var target_node: Node3D
var integrity:   StructuralIntegrity   # query path only (has_part)


func _init(p_node: Node3D, p_integrity: StructuralIntegrity) -> void:
    target_node = p_node
    integrity   = p_integrity

func validate() -> bool:
    return integrity.has_part(target_node)

func execute() -> void:
    VoxelEventBus.emit(
        PartRemovedEvent.CHANNEL,
        PartRemovedEvent.new(GRID_ID, target_node))
    target_node.queue_free()
