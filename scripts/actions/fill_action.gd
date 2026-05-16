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
    # This is the principled fix for bug2c on the fill path; it replaces
    # the old _push_player_above_terrain scaffolding.
    if player != null:
        var dist := player.global_position.distance_to(position)
        if dist <= radius + PLAYER_CLEARANCE:
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
