class_name PlayerSafeAction
extends Action

# Common parent for terrain edits near the player. A player edit must never bury them
# (push solid into their body) nor drop them out of the world (carve the ground from
# under their feet). This is the single source of truth for those two danger volumes;
# subclasses test cells against `buries()` / `drops()` rather than re-deriving boxes.

var player: CharacterBody3D

# The player's body box and the support box just below the feet, sized for the
# ~0.5 m-radius, 3 m-tall capsule. The one place these extents live.
const _CAPSULE_MIN  := Vector3(-0.6, -1.5, -0.6)
const _CAPSULE_SIZE := Vector3(1.2, 3.0, 1.2)
const _SUPPORT_MIN  := Vector3(-0.6, -3.0, -0.6)
const _SUPPORT_SIZE := Vector3(1.2, 1.5, 1.2)


static func capsule_box(player_pos: Vector3) -> AABB:
    return AABB(player_pos + _CAPSULE_MIN, _CAPSULE_SIZE)

static func support_box(player_pos: Vector3) -> AABB:
    return AABB(player_pos + _SUPPORT_MIN, _SUPPORT_SIZE)


# A cell that becomes SOLID inside the capsule would bury the player.
func buries(cell: Vector3i) -> bool:
    return player != null \
        and capsule_box(player.global_position).has_point(Vector3(cell) + VoxelConstants.VOXEL_CENTER_OFFSET)

# A cell that becomes AIR inside the support box would drop the player.
func drops(cell: Vector3i) -> bool:
    return player != null \
        and support_box(player.global_position).has_point(Vector3(cell) + VoxelConstants.VOXEL_CENTER_OFFSET)
