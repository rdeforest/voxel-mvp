extends GutTest

# Every write to matter announces itself once, credited to the source its ActionContext names, so
# a subscriber can tell a player's edit from a replayed or instrumented one by fact
# (EditSource, docs/roadmap/design/04-event-bus.md). The MPM thaw and freeze are pinned in
# test_mpm_structure. (Drafted by Claude, overnight 2026-09-27.)

const MatterLog := preload("res://test/support/matter_log.gd")

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

const COLUMN_X := 100.0
const COLUMN_Z := 100.0

var _log: MatterLog


func before_each() -> void:
    _log = MatterLog.new()

func after_each() -> void:
    _log = null


func _store() -> EditStore:
    var store := EditStore.new()
    store.setup(Vector3(-128.0, -128.0, -128.0), 256.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return store

# The generator's surface point in the column (dx, dz) metres from the test column.
func _ground(dx: float, dz: float) -> Vector3:
    var x := COLUMN_X + dx
    var z := COLUMN_Z + dz
    return Vector3(x, EditStore.terrain_surface(x, z, BASE, AMP, PERIOD, OCTAVES, SEED), z)

func _cell(p: Vector3) -> Vector3i:
    return Vector3i(p.floor())


# One of each writing Action, each aimed where it writes, in its own column. REPLAY is not the
# context's default, so an action that ignored its context's source would be caught crediting PLAYER.
func _actions(ctx: ActionContext) -> Dictionary:
    var slab := preload("res://assets/parts/slab/slab.tres")
    return {
        "fill":         FillAction.new(_ground(0.6, 0.2) + Vector3.UP * 0.9, 2.6, ctx, &"Wood"),
        "dig":          DigAction.new(_ground(-8.4, 0.7) + Vector3.DOWN * 0.8, 2.6, ctx),
        "fill_voxel":   FillVoxelAction.new(_cell(_ground(0.0, 8.0)) + Vector3i(0, 8, 0), ctx, &"Stone"),
        "empty_voxel":  EmptyVoxelAction.new(_cell(_ground(0.0, -8.0)) + Vector3i(0, -6, 0), ctx),
        "raise":        RaiseAction.new(_ground(8.4, 0.6), 3.0, ctx),
        "lower":        LowerAction.new(_ground(-16.3, 0.2), 3.0, ctx),
        "flatten":      FlattenAction.new(_ground(16.3, 0.8) + Vector3.DOWN * 0.6, Vector3.UP, 3.0, ctx),
        "csg":          CsgAction.new(CsgBoxShape.new(Vector3(2.0, 2.0, 2.0)),
                            Transform3D(Basis(), _ground(0.0, -16.0) + Vector3.UP * 30.0),
                            CsgState.Op.ADD, &"Wood", ctx),
        "construction": ConstructionAction.new(slab, _ground(0.5, 16.5) + Vector3.DOWN * 0.4, Vector3.ZERO,
                            &"Wood", ctx),
    }


func test_every_action_credits_its_contexts_source() -> void:
    var store   := _store()
    var actions := _actions(ActionContext.new(store, null, null, EditSource.Kind.REPLAY))
    for name: String in actions:
        var action: Action = actions[name]
        assert_true(action.validate(), "%s: precondition, the action is valid here" % name)
        _log.clear()
        action.execute()
        assert_eq(_log.sources(), [EditSource.Kind.REPLAY] as Array[EditSource.Kind],
            "%s: one matter-changed event, credited to the context's source" % name)
        assert_false(_log.events.is_empty() or _log.events[0].flips.is_empty(),
            "%s: and it carries the cells it flipped (else this tests nothing)" % name)


func test_the_players_context_credits_the_player() -> void:
    var factories := ActionFactories.new(null, null, null, null, null)
    factories._store_ref = _store()
    assert_eq(factories._action_ctx().source, EditSource.Kind.PLAYER, "ActionFactories builds a PLAYER context")
