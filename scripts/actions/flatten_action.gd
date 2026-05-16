class_name FlattenAction
extends Action

# Note: this preserves the original flatten geometry. The bounding box is
# centered on `center` (the inward-offset point), but the plane itself runs
# through `plane_point` (the surface hit). This asymmetry lets the bounding
# box reach material on both sides of the surface without the plane drifting
# inward from where the player clicked.
var center:      Vector3   # center of the affected bounding box
var plane_point: Vector3   # a point the flatten plane passes through
var normal:      Vector3   # normal of the flatten plane
var radius:      float

var terrain:     VoxelLodTerrain
var player:      CharacterBody3D  # for fall-through prevention

# Clearance below the plane within which the action is refused if the
# player is in the affected lateral region. Tracks the player capsule.
const PLAYER_CLEARANCE := 1.0

func _init(
    p_center:      Vector3,
    p_plane_point: Vector3,
    p_normal:      Vector3,
    p_radius:      float,
    p_terrain:     VoxelLodTerrain,
    p_player:      CharacterBody3D,
) -> void:
    center      = p_center
    plane_point = p_plane_point
    normal      = p_normal.normalized()
    radius      = p_radius
    terrain     = p_terrain
    player      = p_player

func validate() -> bool:
    # Refuse-don't-deform: if flattening would bury the player, refuse.
    # The plane equation tells us which side of the plane the player is on;
    # if the player is on the "fill" side (negative plane distance) and
    # within lateral radius of the action, refuse.
    if player != null:
        var player_pos    := player.global_position
        var plane_dist    : float = normal.dot(player_pos - plane_point)
        var lateral_off   := player_pos - plane_point - normal * plane_dist
        var within_radius := lateral_off.length() <= radius

        # plane_dist < clearance means player is on the fill side or too
        # close to the surface to be safe.
        if within_radius and plane_dist < PLAYER_CLEARANCE:
            return false
    return true

func execute() -> void:
    if terrain == null:
        push_error("FlattenAction.execute(): no terrain")
        return

    var voxel_tool := terrain.get_voxel_tool()
    voxel_tool.channel = VoxelBuffer.CHANNEL_SDF

    var origin     := center - Vector3.ONE *  radius
    var dimensions :=          Vector3.ONE * (radius * 2.0)

    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(pos: Vector3i) -> void:
            var plane_dist: float = normal.dot(Vector3(pos) - plane_point)
            voxel_tool.set_voxel_f(pos, plane_dist)
    )
