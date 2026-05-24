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

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    if integrity.part_support.part_registry.has(target_node):
        var data: PartData = integrity.part_support.part_registry[target_node]
        p.air = data.cells.duplicate()
    return p

func execute() -> void:
    VoxelEventBusSingleton.emit(
        PartRemovedEvent.CHANNEL,
        PartRemovedEvent.new(GRID_ID, target_node))
    target_node.queue_free()
