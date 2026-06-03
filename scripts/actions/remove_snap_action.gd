class_name RemoveSnapAction
extends Action

# Removes the snap point on a placed part nearest the cursor, within max_dist.
# Refuses when the targeted part has no point in reach. Removing an inherited
# point forks the instance from its prototype first (see SnapPoints).

var node:        Node3D
var world_point: Vector3
var max_dist:    float
var proto:       Array     # prototype's snap points, for copy-on-write fork
var integrity:   StructuralIntegrity   # query path only (has_part)


func _init(p_node: Node3D, p_point: Vector3, p_max_dist: float, p_proto: Array, p_integrity: StructuralIntegrity) -> void:
    node        = p_node
    world_point = p_point
    max_dist    = p_max_dist
    proto       = p_proto
    integrity   = p_integrity

func validate() -> bool:
    if node == null or not integrity.has_part(node):
        return false
    return SnapPoints.nearest_world(node, world_point, max_dist, proto) != null

func execute() -> void:
    SnapPoints.remove_nearest(node, world_point, max_dist, proto)
