extends GutTest

# actions-preview-gdscript-slow: preview() runs every frame, so it must not be GDScript-bound. Each
# action's preview() for a radius-3 brush on the game's store at a real surface point, with the
# player at the brush's edge (the safety scan runs in full), against the GDScript oracle doing the
# same prediction — in the same process, so machine load hits both. Measured about 20x apart, so
# MIN_SPEEDUP is headroom, not a tuned number; against the all-GDScript previews the ratio is
# about 1. test_edit_store_predict gates that the two agree; scripts/dev/bench_preview_predict.gd
# prints the absolute times.

const Oracle := preload("res://test/support/lattice_oracle.gd")

const MIN_SPEEDUP := 5.0

var _store: EditStore
var _at:    Vector3


func before_each() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store = manager.store
    _at    = Vector3(100.0, EditStore.terrain_surface(100.0, 106.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED), 106.0)


func test_previews_are_not_gdscript_bound() -> void:
    var body := CharacterBody3D.new()
    add_child_autofree(body)
    body.global_position = _at + Vector3(4.5, 1.5, 0.0)

    var ctx   := ActionContext.new(_store, body, null)
    var shape := CsgSphereShape.new(3.0)
    var xform := Transform3D(Basis(), _at)
    var cases := {
        "dig": [func() -> Action: return DigAction.new(_at, 3.0, ctx),
            func() -> void: Oracle.flips(Oracle.sphere_stamp(_store, _at, 3.0, VoxelConstants.STORE_OP_SUBTRACT, 1.0), _store)],
        "fill": [func() -> Action: return FillAction.new(_at, 3.0, ctx),
            func() -> void: Oracle.flips(Oracle.sphere_stamp(_store, _at, 3.0, VoxelConstants.STORE_OP_UNION, 1.0), _store)],
        "raise": [func() -> Action: return RaiseAction.new(_at, 3.0, ctx),
            func() -> void: _oracle_preview(Oracle.work(_store, Oracle.bell_work(_store, _at, 3.0, -1.0)), body)],
        "flatten": [func() -> Action: return FlattenAction.new(_at, Vector3.UP, 3.0, ctx),
            func() -> void: _oracle_preview(Oracle.work(_store, Oracle.flatten_work(_store, _at, Vector3.UP, 3.0)), body)],
        "CSG sphere": [func() -> Action: return CsgAction.new(shape, xform, CsgState.Op.ADD, &"Stone", ctx),
            func() -> void: _oracle_preview(Oracle.imprint(_store, shape, xform, CsgState.Op.ADD), body)],
    }
    for label: String in cases:
        var make: Callable = cases[label][0]
        assert_false(make.call().preview().is_empty(), "%s: the preview names cells (else it is cheap for nothing)" % label)
        var best   := _best_usec(func() -> void: make.call().preview(), cases[label][1])
        var game   := best.x
        var oracle := best.y
        assert_gt(oracle, game * MIN_SPEEDUP, "%s preview(): %.0f us vs the GDScript oracle's %.0f us" % [label, game, oracle])


func _oracle_preview(lat: SdfLattice, body: CharacterBody3D) -> void:
    Oracle.flips(lat, _store)
    var _endangered := Oracle.turns_in(lat, _store, PlayerSafeAction.capsule_box(body.global_position), true) \
        or Oracle.turns_in(lat, _store, PlayerSafeAction.support_box(body.global_position), false)


# Best of five 10-call batches each, per call, as (game, oracle). The batches alternate so a load
# spike lands on both sides rather than on one.
func _best_usec(game: Callable, oracle: Callable) -> Vector2:
    var best := Vector2(INF, INF)
    for _trial in 5:
        best.x = minf(best.x, _batch_usec(game))
        best.y = minf(best.y, _batch_usec(oracle))
    return best


func _batch_usec(body: Callable) -> float:
    var start := Time.get_ticks_usec()
    for _i in 10:
        body.call()
    return float(Time.get_ticks_usec() - start) / 10.0
