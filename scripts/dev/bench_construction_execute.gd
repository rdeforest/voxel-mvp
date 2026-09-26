extends GutTest

# execute() on a fresh game store each rep (so every rep really writes), for the actions whose write
# paints materials: ConstructionAction (the beam resting on the surface, turned 0 and 45 degrees),
# CsgAction (a box and a sphere, ADD and SUBTRACT, at the surface), FillAction and DigAction (a
# sphere at the surface). Only execute() is timed; the store setup and the validate()/preview()
# that precede it in play are outside the clock, as they are already cached by the time the player
# commits.
# Run: bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/dev/bench_construction_execute.gd
# (Drafted by Claude, overnight 2026-09-26.)

const REPS := 200


func test_bench() -> void:
    var beam := preload("res://assets/parts/beam/beam.tres")
    for yaw: float in [0.0, 45.0]:
        _time("beam yaw %2.0f" % yaw, func(store: EditStore, at: Vector3) -> Action:
            return ConstructionAction.new(beam, at, Vector3(0.0, yaw, 0.0), &"Wood", _ctx(store)))
    var shapes: Array[CsgShape] = [CsgBoxShape.new(Vector3(4.0, 4.0, 4.0)), CsgSphereShape.new(2.0)]
    for shape in shapes:
        for op in [CsgState.Op.ADD, CsgState.Op.SUBTRACT]:
            _time("csg %s %s op %d" % [shape.sdf_kind(), shape.sdf_dims(), op], func(store: EditStore, at: Vector3) -> Action:
                return CsgAction.new(shape, Transform3D(Basis(Vector3.UP, 0.3), at), op, &"Stone", _ctx(store)))
    _time("fill r2", func(store: EditStore, at: Vector3) -> Action:
        return FillAction.new(at + Vector3(0.3, 0.1, -0.2), 2.0, _ctx(store), &"Stone"))
    _time("dig r2", func(store: EditStore, at: Vector3) -> Action:
        return DigAction.new(at + Vector3(0.3, 0.1, -0.2), 2.0, _ctx(store)))
    pass_test("timings printed")


func _time(label: String, make: Callable) -> void:
    var spent := 0
    for i in REPS + 1:
        var action := _primed(make)
        var start  := Time.get_ticks_usec()
        action.execute()
        if i > 0:
            spent += Time.get_ticks_usec() - start
    print("%-24s execute() %.4f ms" % [label, float(spent) / 1000.0 / REPS])


func _ctx(store: EditStore) -> ActionContext:
    return ActionContext.new(store, null, null)


func _primed(make: Callable) -> Action:
    var manager := EditStoreManager.new()
    manager.setup()
    var at := Vector3(100.0, EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED), 100.0)
    var action: Action = make.call(manager.store, at)
    action.preview()
    return action
