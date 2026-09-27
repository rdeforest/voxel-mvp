extends SceneTree

# Times the MPM freeze (MpmSim.rasterize_to_store) on the game's field, for
# doc 12 ("The freeze (as built)"): the 9^3 buried block test_mpm_structure thaws, and the
# floating 10^3 block bench_mpm_thaw thaws (the largest thaw a bench produces; settled and frozen here).
#
#   godot --path . --headless -s res://scripts/dev/bench_mpm_freeze.gd


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    await process_frame
    load("res://scripts/dev/bench_mpm_freeze_work.gd").run()
    quit()
