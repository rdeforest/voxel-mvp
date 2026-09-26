extends GutTest

# ConstructionAction.execute() on a fresh game store each rep (so every rep really writes), for
# the beam resting on the surface, turned 0 and 45 degrees. Only execute() is timed; the store
# setup and the validate()/preview() that precede it in play are outside the clock, as they are
# already cached by the time the player commits.
# Run: bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/dev/bench_construction_execute.gd
# (Drafted by Claude, overnight 2026-09-26.)

const REPS := 200


func test_bench() -> void:
    var beam := preload("res://assets/parts/beam/beam.tres")
    for yaw: float in [0.0, 45.0]:
        var spent := 0
        for i in REPS + 1:
            var action := _primed(beam, yaw)
            var start  := Time.get_ticks_usec()
            action.execute()
            if i > 0:
                spent += Time.get_ticks_usec() - start
        print("beam yaw %2.0f  execute() %.4f ms" % [yaw, float(spent) / 1000.0 / REPS])
    pass_test("timings printed")


func _primed(beam: Part, yaw: float) -> ConstructionAction:
    var manager := EditStoreManager.new()
    manager.setup()
    var at := Vector3(100.0, EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED), 100.0)
    var action := ConstructionAction.new(beam, at, Vector3(0.0, yaw, 0.0), &"Wood",
        ActionContext.new(manager.store, null, null))
    action.preview()
    return action
