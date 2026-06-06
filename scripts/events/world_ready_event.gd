class_name WorldReadyEvent
extends VoxelEvent

# Fired once per world start/reset, when terrain data around the player has
# actually streamed in. Gameplay + physics systems start inactive and resume on
# this — so nothing acts on a half-loaded world (player falling through ungrown
# ground, PBD anchoring against terrain that isn't there yet, etc.). Global, not
# spatial: subscribe channel-wide (`subscribe`, not `subscribe_cell`).

const CHANNEL := &"world_ready"


func _init(p_grid_id: int = 0) -> void:
    grid_id = p_grid_id
