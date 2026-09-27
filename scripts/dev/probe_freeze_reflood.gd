extends SceneTree

# Can a DetachmentScout that seeds from an MPM freeze's measured flips re-flood, and re-thaw, the
# pile the freeze just deposited, in a loop? Runs falls that end in a freeze onto the game's terrain
# (test/support/scenario.gd) and counts the scout's floods, their verdicts and its thaws per case.
# The scout ignores freezes, so this measures the baseline; to measure seeding, make _on_edit seed
# MPM events as it seeds SCOUT ones (https://github.com/rdeforest/voxel-mvp/issues/20: the grid post loops).
#
#   godot --path . --headless -s res://scripts/dev/probe_freeze_reflood.gd


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    await process_frame
    load("res://scripts/dev/probe_freeze_reflood_work.gd").run(root)
    quit()
