extends GutHookScript

# Claims this run's own directory before the first test, so the game's save and recording roots
# point into it before any test can reach them. test/support/run_paths.gd.
# (Drafted by Claude, overnight 2026-09-27.)

const RunPaths := preload("res://test/support/run_paths.gd")


func run() -> void:
    print("test files under %s" % ProjectSettings.globalize_path(RunPaths.root()))
