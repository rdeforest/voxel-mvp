extends SceneTree

# Times MpmStructure.thaw_cells on the game's field: terrain spheres and a floating block (the
# shape the detachment auto-trigger thaws). Measured for docs/roadmap/design/
# 12-mpm-structural-substrate.md ("The thaw carve").
#
#   godot --path . --headless -s res://scripts/dev/bench_mpm_thaw.gd


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    await process_frame
    load("res://scripts/dev/bench_mpm_thaw_work.gd").run()
    quit()
