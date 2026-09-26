extends GutTest

# actions-preview-gdscript-slow: time per preview() call for a radius-3 brush on the game's store at
# a real surface point — the renderer's per-frame cost — for dig, fill, raise, flatten and CSG
# sphere, against the same prediction done by the GDScript oracle (test/support/lattice_oracle.gd,
# the code previews ran before EditStore took it over). Also a construction beam resting on the
# surface and floating 3 m above it, where the attach scan finds nothing and runs in full. Two
# player cases: none (the bug file's table), and one standing at the brush's edge, where the safety
# boxes overlap rewritten leaves but nothing is endangered, so the safety scan runs in full.
# Run (GUT, for the autoloads): bin/godot --path . --headless -s addons/gut/gut_cmdln.gd \
#     -gtest=res://scripts/dev/bench_preview_predict.gd

const Oracle := preload("res://test/support/lattice_oracle.gd")

const RADIUS := 3.0
const REPS   := 300

var _store: EditStore
var _at:    Vector3


func test_bench() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store = manager.store
    _at    = Vector3(100.0, EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED), 100.0)
    _rows("no player", null)
    var body := CharacterBody3D.new()
    add_child_autofree(body)
    body.global_position = _at + Vector3(4.5, 1.5, 0.0)
    _rows("player at the brush's edge", body)
    pass_test("timings printed")


func _rows(label: String, player: CharacterBody3D) -> void:
    print("--- %s ---" % label)
    var ctx   := ActionContext.new(_store, player, null)
    var shape := CsgSphereShape.new(RADIUS)
    var xform := Transform3D(Basis(), _at)
    var sub   := VoxelConstants.STORE_OP_SUBTRACT
    var add   := VoxelConstants.STORE_OP_UNION
    _row("dig", func() -> void: DigAction.new(_at, RADIUS, ctx).preview(),
        func() -> void: Oracle.flips(Oracle.sphere_stamp(_store, _at, RADIUS, sub, 1.0), _store))
    _row("fill", func() -> void: FillAction.new(_at, RADIUS, ctx).preview(),
        func() -> void: Oracle.flips(Oracle.sphere_stamp(_store, _at, RADIUS, add, 1.0), _store))
    _row("raise", func() -> void: RaiseAction.new(_at, RADIUS, ctx).preview(),
        func() -> void: _oracle_safe(Oracle.work(_store, Oracle.bell_work(_store, _at, RADIUS, -1.0)), player))
    _row("flatten", func() -> void: FlattenAction.new(_at, Vector3.UP, RADIUS, ctx).preview(),
        func() -> void: _oracle_safe(Oracle.work(_store, Oracle.flatten_work(_store, _at, Vector3.UP, RADIUS)), player))
    _row("CSG sphere", func() -> void: CsgAction.new(shape, xform, CsgState.Op.ADD, &"Stone", ctx).preview(),
        func() -> void: _oracle_safe(Oracle.imprint(_store, shape, xform, CsgState.Op.ADD), player))
    for lift in [0.0, 3.0]:
        var beam  := preload("res://assets/parts/beam/beam.tres")
        var build := ConstructionAction.new(beam, _at + Vector3.UP * lift, Vector3.ZERO, &"Wood", ctx)
        _row("beam +%.0f m" % lift, func() -> void:
                ConstructionAction.new(beam, _at + Vector3.UP * lift, Vector3.ZERO, &"Wood", ctx).preview(),
            func() -> void: _oracle_build(build, player))


# A construction preview as the oracle asks it: the imprint, its flips and safety, and the attach scan.
func _oracle_build(build: ConstructionAction, player: CharacterBody3D) -> void:
    var lat := Oracle.imprint(_store, build._shape(), build._xform(), CsgState.Op.ADD)
    _oracle_safe(lat, player)
    var _attached := Oracle.attached(_store, lat, build._shape(), build._xform())


# The oracle's flips plus, with a player, its safety scan: what a PlayerSafeAction preview asked.
func _oracle_safe(lat: SdfLattice, player: CharacterBody3D) -> void:
    Oracle.flips(lat, _store)
    if player != null:
        var at := player.global_position
        var _endangered := Oracle.turns_in(lat, _store, PlayerSafeAction.capsule_box(at), true) \
            or Oracle.turns_in(lat, _store, PlayerSafeAction.support_box(at), false)


func _ms(body: Callable) -> float:
    body.call()
    var start := Time.get_ticks_usec()
    for _i in REPS:
        body.call()
    return float(Time.get_ticks_usec() - start) / 1000.0 / REPS


func _row(label: String, game: Callable, oracle: Callable) -> void:
    print("%-12s preview() %.3f ms   GDScript oracle %.3f ms" % [label, _ms(game), _ms(oracle)])
