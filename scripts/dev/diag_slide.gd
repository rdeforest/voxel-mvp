extends SceneTree

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    await process_frame
    load("res://scripts/dev/diag_slide_work.gd").run()
    quit()
