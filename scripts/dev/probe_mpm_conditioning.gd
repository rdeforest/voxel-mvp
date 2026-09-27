extends SceneTree

# Runs the MPM thaws the game and tests exercise and reports, per scenario, the smallest
# |σ₂|/σ₀ any SVD in the sim saw and the mean step time. Evidence for
# https://github.com/rdeforest/voxel-mvp/issues/17.
#
#   godot --path . --headless -s res://scripts/dev/probe_mpm_conditioning.gd


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    await process_frame
    load("res://scripts/dev/probe_mpm_conditioning_work.gd").run()
    quit()
