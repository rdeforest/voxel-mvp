extends GutTest

# Every gameplay action survives action -> step -> step file -> step -> action: the rebuilt action
# writes the same step text, validates and previews the same on the game's store, and executing
# each on its own copy of that store leaves the two stores byte-identical. Positions carry thirds
# and tenths so an inexact number would show. docs/roadmap/design/22-scenario-languages.md.

const COLUMN := Vector2(100.0, 100.0)
const THIRD  := 1.0 / 3.0

var _surface: float
var _stores:  Array[EditStore] = []


func before_each() -> void:
    _fresh_stores()
    _surface = EditStore.terrain_surface(COLUMN.x, COLUMN.y, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


# Two identical game stores: the original action runs on 0, the rebuilt one on 1.
func _fresh_stores() -> void:
    _stores = [_game_store(), _game_store()]

func _game_store() -> EditStore:
    var manager := EditStoreManager.new()
    manager.setup()
    return manager.store

func _ctx(i: int, player: CharacterBody3D = null) -> ActionContext:
    return ActionContext.new(_stores[i], player, null, EditSource.Kind.REPLAY)

func _at(dx: float, dy: float, dz: float) -> Vector3:
    return Vector3(COLUMN.x + dx, _surface + dy, COLUMN.y + dz)


# --- The round trip ---

func _through_file(step: Dictionary) -> Dictionary:
    var doc := StepDocument.new()
    doc.steps = [step]
    var text := doc.write()
    assert_eq(doc.error, "", "the step writes")
    var back := StepDocument.new()
    assert_true(back.read(text), "the file reads back: %s" % back.error)
    return back.steps[0] if back.steps.size() == 1 else {}

func _step_text(action: Action) -> String:
    return StepJson.new().stringify(StepRegistry.step_of(action))

func _same_preview(a: ActionPreview, b: ActionPreview) -> bool:
    return a.air == b.air and a.solid == b.solid and a.part == b.part and a.refused == b.refused

# `make` builds the action in a context; it is called for store 0, and the step rebuilds it for
# store 1.
func _assert_round_trip(what: String, make: Callable, execute := true) -> void:
    _fresh_stores()
    var original: Action = make.call(_ctx(0))
    var fields := StepFields.new(_through_file(StepRegistry.step_of(original)))
    var rebuilt := StepRegistry.action_of(fields, _ctx(1))
    assert_not_null(rebuilt, "%s rebuilds (%s)" % [what, fields.error])
    if rebuilt == null:
        return
    assert_eq(rebuilt.get_script(), original.get_script(), "%s rebuilds as the same class" % what)
    assert_eq(_step_text(rebuilt), _step_text(original), "%s: the same step, bit for bit" % what)
    assert_eq(rebuilt.validate(), original.validate(), "%s: validate() agrees" % what)
    var preview := original.preview()
    assert_false(preview.is_empty(), "%s: the preview shows something, so agreeing means something" % what)
    assert_true(_same_preview(rebuilt.preview(), preview), "%s: preview() agrees" % what)
    if execute:
        _assert_same_execute(what, original, rebuilt)

func _assert_same_execute(what: String, original: Action, rebuilt: Action) -> void:
    var before := _stores[0].serialize()
    original.execute()
    rebuilt.execute()
    assert_ne(_stores[0].serialize(), before, "%s: executing changes the store" % what)
    assert_eq(_stores[1].serialize(), _stores[0].serialize(), "%s: both stores end byte-identical" % what)


func test_dig() -> void:
    _assert_round_trip("dig", func(ctx: ActionContext) -> Action:
        return DigAction.new(_at(THIRD, -0.1, 0.1), 3.0, ctx))

func test_fill() -> void:
    _assert_round_trip("fill", func(ctx: ActionContext) -> Action:
        return FillAction.new(_at(0.1, 1.3, THIRD), 3.0, ctx, &"Sand"))

func test_raise() -> void:
    _assert_round_trip("raise", func(ctx: ActionContext) -> Action:
        return RaiseAction.new(_at(THIRD, 0.0, 0.7), 3.0, ctx))

func test_lower() -> void:
    _assert_round_trip("lower", func(ctx: ActionContext) -> Action:
        return LowerAction.new(_at(0.7, 0.0, THIRD), 3.0, ctx))

func test_fill_voxel() -> void:
    var cell := Vector3i(int(COLUMN.x), floori(_surface) + 1, int(COLUMN.y))
    _assert_round_trip("fill_voxel", func(ctx: ActionContext) -> Action:
        return FillVoxelAction.new(cell, ctx, &"Metal"))

func test_empty_voxel() -> void:
    var cell := _emptiable_surface_cell()
    assert_ne(cell, Vector3i.MAX, "some surface cell can be emptied")
    _assert_round_trip("empty_voxel", func(ctx: ActionContext) -> Action:
        return EmptyVoxelAction.new(cell, ctx))

func test_probe() -> void:
    _assert_round_trip("probe", func(ctx: ActionContext) -> Action:
        return ProbeAction.new(_at(0.2, 0.0, 0.4), Vector3.UP, Vector3(0.0, 1.0, THIRD), ctx), false)

func _emptiable_surface_cell() -> Vector3i:
    for y in range(floori(_surface), floori(_surface) - 4, -1):
        var cell := Vector3i(int(COLUMN.x), y, int(COLUMN.y))
        if EmptyVoxelAction.new(cell, _ctx(0)).validate():
            return cell
    return Vector3i.MAX


# The plane's normal is kept as given: renormalizing a unit vector moves about a third of them an
# ulp, so a step holding the normalized normal would rebuild a different plane.
func test_flatten_keeps_the_normal_as_given() -> void:
    var given := Vector3(-0.9, 1.0, -0.3)
    assert_ne(given.normalized().normalized(), given.normalized(), "precondition: this normal moves on renormalizing")
    _assert_round_trip("flatten", func(ctx: ActionContext) -> Action:
        return FlattenAction.new(_at(0.3, 0.37, 0.1), given, 3.0, ctx))


func test_csg_every_shape_and_mode() -> void:
    var xform := Transform3D(VoxelUtils.euler_basis(Vector3(15.0, 30.0, -7.5)), _at(0.1, 0.0, 0.3))
    var cases := {
        "csg box add":           [CsgBoxShape.new(Vector3(4.0, 1.5, 2.0 + THIRD)), CsgState.Op.ADD],
        "csg cylinder subtract": [CsgCylinderShape.new(1.5, 2.0 + THIRD), CsgState.Op.SUBTRACT],
        "csg sphere add":        [CsgSphereShape.new(2.0 + THIRD), CsgState.Op.ADD],
    }
    for what: String in cases:
        var shape: CsgShape = cases[what][0]
        var op: int = cases[what][1]
        _assert_round_trip(what, func(ctx: ActionContext) -> Action:
            return CsgAction.new(shape, xform, op, &"Stone", ctx))

# The step holds the shape by value: resizing the live shape afterwards doesn't reach it.
func test_csg_step_is_a_snapshot_of_the_shape() -> void:
    var shape := CsgBoxShape.new(Vector3(2.0, 2.0, 2.0))
    var step := StepRegistry.step_of(CsgAction.new(shape, Transform3D.IDENTITY, CsgState.Op.ADD, &"Stone", _ctx(0)))
    shape.grow(0, 5.0)
    assert_eq(step["dims"], [2.0, 2.0, 2.0])


func test_build_from_a_part_file() -> void:
    var beam: Part = preload("res://assets/parts/beam/beam.tres")
    _assert_round_trip("build beam", func(ctx: ActionContext) -> Action:
        return ConstructionAction.new(beam, _at(0.1, 0.0, 0.2), Vector3(0.0, 22.5, 3.0 + THIRD), &"Wood", ctx))

func test_build_an_inline_part() -> void:
    var part := Part.new()
    part.dimensions = Vector3(1.5, 0.25 + THIRD, 3.0)
    _assert_round_trip("build inline", func(ctx: ActionContext) -> Action:
        return ConstructionAction.new(part, _at(0.1, 0.0, 0.2), Vector3(0.0, 10.0, 0.0), &"Wood", ctx))


# The player's position is the step stream's, not the step's: a rebuilt action reads whichever
# player its context holds, so the same step refuses beside one player and not another.
func test_player_position_is_not_in_the_step() -> void:
    var at := _at(0.5, 2.0, 0.5)
    var near := CharacterBody3D.new()
    add_child_autofree(near)
    near.global_position = at
    var step := StepRegistry.step_of(FillAction.new(at, 1.0, _ctx(0, near), &"Stone"))
    assert_false(JSON.stringify(step).contains("player"), "no player field")

    assert_false(StepRegistry.action_of(StepFields.new(step), _ctx(1, near)).validate(), "refused beside the player")
    assert_true(StepRegistry.action_of(StepFields.new(step), _ctx(1)).validate(), "allowed with no player there")


# --- Arbitrary arguments ---

# A constructor that normalizes, wraps, snaps or clamps an argument (flatten's normal did) moves
# only some values, so each op is rebuilt from many random ones: non-unit normals, rotations past
# 360, sheared transforms, thirds. The rebuilt action must write the step it was rebuilt from.
const RANDOM_ROUNDS := 100

var _rng := RandomNumberGenerator.new()


func test_every_op_rebuilds_arbitrary_arguments_exactly() -> void:
    _rng.seed = 20260927
    var makers := _random_makers()
    assert_eq(makers.keys().size(), StepRegistry.ops().size(), "a random maker for every op")
    for op: String in StepRegistry.ops():
        assert_true(makers.has(op), "%s has a random maker" % op)
        for attempt in RANDOM_ROUNDS:
            var original: Action = makers[op].call()
            var fields := StepFields.new(_through_file(StepRegistry.step_of(original)))
            var rebuilt := StepRegistry.action_of(fields, _ctx(1))
            if rebuilt == null or _step_text(rebuilt) != _step_text(original):
                fail_test("%s round %d: %s -> %s" % [op, attempt, _step_text(original),
                    fields.error if rebuilt == null else _step_text(rebuilt)])
                break

func _random_makers() -> Dictionary:
    var ctx := _ctx(0)
    return {
        "dig":         func() -> Action: return DigAction.new(_rvec(), _rpos(), ctx),
        "fill":        func() -> Action: return FillAction.new(_rvec(), _rpos(), ctx, _rmaterial()),
        "raise":       func() -> Action: return RaiseAction.new(_rvec(), _rpos(), ctx),
        "lower":       func() -> Action: return LowerAction.new(_rvec(), _rpos(), ctx),
        "flatten":     func() -> Action: return FlattenAction.new(_rvec(), _rvec(), _rpos(), ctx),
        "probe":       func() -> Action: return ProbeAction.new(_rvec(), _rvec(), _rvec(), ctx),
        "fill_voxel":  func() -> Action: return FillVoxelAction.new(_rcell(), ctx, _rmaterial()),
        "empty_voxel": func() -> Action: return EmptyVoxelAction.new(_rcell(), ctx),
        "csg":         func() -> Action: return CsgAction.new(_rshape(), _rxform(), _rng.randi_range(0, 1), _rmaterial(), ctx),
        "build":       func() -> Action: return ConstructionAction.new(_rpart(), _rvec(), _rvec() * 1000.0, _rmaterial(), ctx),
    }

# Magnitudes from 1e-3 to 1e3, half of them a third of something so the decimal never ends.
func _rpos() -> float:
    var x := _rng.randf() * pow(10.0, _rng.randi_range(-3, 3))
    return x / 3.0 if _rng.randi() % 2 == 0 else x

func _rvec() -> Vector3:
    return Vector3(_rsigned(), _rsigned(), _rsigned())

func _rsigned() -> float:
    return _rpos() * (1.0 if _rng.randi() % 2 == 0 else -1.0)

func _rcell() -> Vector3i:
    return Vector3i(_rng.randi_range(-100000, 100000), _rng.randi_range(-1000, 1000), _rng.randi_range(-100000, 100000))

func _rxform() -> Transform3D:
    return Transform3D(Basis(_rvec(), _rvec(), _rvec()), _rvec())

func _rmaterial() -> StringName:
    return MaterialPalette.NAMES[_rng.randi_range(1, MaterialPalette.NAMES.size() - 1)]

func _rshape() -> CsgShape:
    var shapes: Array[CsgShape] = [CsgBoxShape.new(_rvec().abs()), CsgCylinderShape.new(_rpos(), _rpos()),
        CsgSphereShape.new(_rpos())]
    return shapes[_rng.randi_range(0, 2)]

func _rpart() -> Part:
    var part := Part.new()
    part.dimensions = _rvec().abs()
    return part


# --- Steps that don't rebuild ---

func _refusal(step: Dictionary) -> String:
    var fields := StepFields.new(step)
    var action := StepRegistry.action_of(fields, _ctx(0))
    assert_null(action, "refused: %s" % [step])
    return fields.error

func _dig_step() -> Dictionary:
    return StepRegistry.step_of(DigAction.new(_at(0.0, 0.0, 0.0), 3.0, _ctx(0)))

func test_malformed_steps_are_refused_with_a_reason() -> void:
    var cases := {
        "op":       {"op": "teleport"},
        "radius":   _dig_step().merged({"radius": "big"}, true),
        "position": _dig_step().merged({"position": [1.0, 2.0]}, true),
        "shape":    _dig_step().merged({"shape": "cube"}, true),
        "extra":    _dig_step().merged({"extra": 1.0}, true),
    }
    var missing := _dig_step()
    missing.erase("radius")
    cases["radius (missing)"] = missing
    for field: String in cases:
        assert_string_contains(_refusal(cases[field]), field.get_slice(" ", 0), "names the field")

func test_unknown_material_is_refused() -> void:
    var step := StepRegistry.step_of(FillVoxelAction.new(Vector3i.ZERO, _ctx(0), &"Stone"))
    step["material"] = "Cheese"
    assert_string_contains(_refusal(step), "material")

func test_fractional_cell_is_refused() -> void:
    var step := StepRegistry.step_of(EmptyVoxelAction.new(Vector3i.ZERO, _ctx(0)))
    step["cell"] = [1.0, 2.5, 3.0]
    assert_string_contains(_refusal(step), "cell")

func test_a_cell_past_32_bits_is_refused() -> void:
    var step := StepRegistry.step_of(EmptyVoxelAction.new(Vector3i.ZERO, _ctx(0)))
    step["cell"] = [3e9, 0.0, 0.0]
    assert_string_contains(_refusal(step), "cell")
    step["cell"] = [-2147483648.0, 2147483647.0, 0.0]
    assert_not_null(StepRegistry.action_of(StepFields.new(step), _ctx(0)), "the int32 extremes are cells")

func test_csg_dims_must_fit_the_shape() -> void:
    var step := StepRegistry.step_of(CsgAction.new(CsgSphereShape.new(2.0), Transform3D.IDENTITY,
        CsgState.Op.ADD, &"Stone", _ctx(0)))
    step["dims"] = [1.0, 2.0]
    assert_string_contains(_refusal(step), "dims")

func test_a_part_file_that_changed_size_is_refused() -> void:
    var beam: Part = preload("res://assets/parts/beam/beam.tres")
    var step := StepRegistry.step_of(ConstructionAction.new(beam, Vector3.ZERO, Vector3.ZERO, &"Wood", _ctx(0)))
    step["dimensions"] = StepFields.encode_vec3(beam.dimensions + Vector3(1.0, 0.0, 0.0))
    assert_string_contains(_refusal(step), "recorded with")

func test_a_missing_part_file_is_refused() -> void:
    var beam: Part = preload("res://assets/parts/beam/beam.tres")
    var step := StepRegistry.step_of(ConstructionAction.new(beam, Vector3.ZERO, Vector3.ZERO, &"Wood", _ctx(0)))
    step["part"] = "res://assets/parts/nope/nope.tres"
    assert_string_contains(_refusal(step), "not a Part")


# --- The file header ---

func test_the_header_is_checked() -> void:
    var doc := StepDocument.new()
    doc.steps = [_dig_step()]
    var text := doc.write()
    assert_true(StepDocument.new().read(text), "its own output reads")
    var edits := {
        "\"version\": 1":                                   "\"version\": 2",
        "\"format\": \"%s\"" % StepDocument.FORMAT:       "\"format\": \"other\"",
        "\"length\": \"meter\"":                          "\"length\": \"foot\"",
    }
    for from: String in edits:
        var edited := text.replace(from, edits[from])
        assert_ne(edited, text, "the edit applies: %s" % from)
        assert_false(StepDocument.new().read(edited), "refuses %s" % edits[from])

func test_one_step_per_line() -> void:
    var doc := StepDocument.new()
    doc.steps = [_dig_step(), _dig_step()]
    var lines := Array(doc.write().split("\n"))
    assert_eq(lines.filter(func(l: String) -> bool: return l.contains("\"op\": \"dig\"")).size(), 2,
        "each step is one line, so trimming is deleting lines")
