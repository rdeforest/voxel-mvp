extends GutHookScript

# Removes this run's own directory. test/support/run_paths.gd.
# (Drafted by Claude, overnight 2026-09-27.)

const RunPaths := preload("res://test/support/run_paths.gd")


func run() -> void:
    RunPaths.release()
