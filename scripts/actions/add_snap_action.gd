class_name AddSnapAction
extends Action

# Adds a snap point to a placed part at the cursor's hit point. The first edit
# forks the instance from its prototype (see SnapPoints); thereafter the point
# lands on this instance alone.

var node:        Node3D
var world_point: Vector3
var proto:       Array     # prototype's snap points, for copy-on-write fork
var integrity:   StructuralIntegrity   # query path only (has_part)


func _init(p_node: Node3D, p_point: Vector3, p_proto: Array, p_integrity: StructuralIntegrity) -> void:
    node        = p_node
    world_point = p_point
    proto       = p_proto
    integrity   = p_integrity

func validate() -> bool:
    return node != null and integrity.has_part(node)

func execute() -> void:
    SnapPoints.add(node, world_point, proto)
