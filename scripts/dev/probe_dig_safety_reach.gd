extends SceneTree

# How far from the player's feet a player-safety refusal on make_dig's brush would reach, on the
# game's field (docs/bugs/dig-action-no-validate-no-safety.md). The work loads after the first
# frame so the actions can see the VoxelEventBusSingleton autoload.
#
#   godot --path . --headless -s res://scripts/dev/probe_dig_safety_reach.gd

func _initialize() -> void:
    await process_frame
    load("res://scripts/dev/probe_dig_safety_reach_work.gd").run(root)
    quit()
