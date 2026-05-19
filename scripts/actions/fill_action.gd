class_name FillAction
extends Action

enum Shape { SPHERE }

var position:  Vector3
var radius:    float
var shape:     int  # Shape enum

var terrain:   VoxelLodTerrain
var integrity: StructuralIntegrity
var player:    CharacterBody3D  # for fall-through prevention

# Clearance beyond the sphere surface within which fills are refused.
# Roughly the player's capsule height; tune if the player capsule changes.
const PLAYER_CLEARANCE := 1.0

func _init(
    p_position:  Vector3,
    p_radius:    float,
    p_terrain:   VoxelLodTerrain,
    p_integrity: StructuralIntegrity,
    p_player:    CharacterBody3D,
    p_shape:     int = Shape.SPHERE,
) -> void:
    position  = p_position
    radius    = p_radius
    shape     = p_shape
    terrain   = p_terrain
    integrity = p_integrity
    player    = p_player

func validate() -> bool:
    # Refuse-don't-deform: if filling would bury the player, refuse.
    if player != null:
        var dist := player.global_position.distance_to(position)
        if dist <= radius + PLAYER_CLEARANCE:
            return false

    # Refuse-don't-deform: if a RigidBody3D occupies the fill volume, refuse.
    # Filling SDF terrain into a body's space lets physics resolve the overlap
    # by squirting the body in an arbitrary direction — usually through the
    # world. Make the player dig the body out or move it first.
    if terrain != null:
        var space := terrain.get_world_3d().direct_space_state
        var query := PhysicsShapeQueryParameters3D.new()
        var sphere := SphereShape3D.new()
        sphere.radius           = radius
        query.shape             = sphere
        query.transform         = Transform3D(Basis(), position)
        query.collide_with_areas = false
        for hit in space.intersect_shape(query, 8):
            if hit.collider is RigidBody3D:
                return false

    return true

func execute() -> void:
    if terrain == null:
        push_error("FillAction.execute(): no terrain")
        return

    var voxel_tool := terrain.get_voxel_tool()
    voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
    voxel_tool.mode    = VoxelTool.MODE_ADD
    voxel_tool.do_sphere(position, radius)

    var origin     := position - Vector3.ONE *  radius
    var dimensions :=            Vector3.ONE * (radius * 2.0)

    # Notify integrity manager of placed voxels. The integrity system
    # decides ground-contact itself during propagation; we just register.
    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(pos: Vector3i) -> void:
            if VoxelUtils.is_in_sphere(Vector3(pos), position, radius):
                integrity.register_voxel(pos, Materials.STONE)
    )

    integrity.notify_terrain_changed(position, radius)
