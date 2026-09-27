extends GutTest

# Doc 22's instrument layer at the console (InstrumentCommands), on a runner world: each exact
# write changes the store exactly as typed, through the normal write path (one matter-changed
# event, credited to INSTRUMENT), bypasses player safety, and switches the player to fly mode only
# when the same check that refuses a player edit says the write endangered them. The writes are
# steps: recorded like a click, they replay to the same store.
# docs/roadmap/design/22-scenario-languages.md, The instrument layer.
# (Drafted by Claude, overnight 2026-09-27.)

const Scenario  := preload("res://test/support/scenario.gd")
const MatterLog := preload("res://test/support/matter_log.gd")
const RunPaths  := preload("res://test/support/run_paths.gd")

# A decimal the engine's own parser (the console's) reads an ulp off, as the precondition checks.
const MISREAD := "100.32314166426659"

var _root := RunPaths.path("test_instruments")
var _dir  := _root + "/take"

var _live: Array[Node] = []
var _s:    Scenario
var _ic:   InstrumentCommands
var _log:  MatterLog
var _heard: Array = []   # [action, valid] per validated signal
var _surface: float      # the ground's height under the player's column


func before_each() -> void:
    _s = Scenario.new()
    add_child(_s)
    _live = [_s]
    assert_true(_s.start_fresh(), "the scenario starts: %s" % _s.error)

    _ic = InstrumentCommands.new()
    _ic.edit_store = _s.manager
    _ic.integrity  = _s.integrity
    _ic.player     = _s.player
    _heard = []
    _ic.validated.connect(func(action: Action, valid: bool) -> void: _heard.append([action, valid]))

    _surface = _surface_at(100.5, 100.5)
    _s.player.global_position = Vector3(100.5, _surface + 1.5, 100.5)
    _log = MatterLog.new()

func after_each() -> void:
    for s in _live:
        if is_instance_valid(s):
            s.free()
    _live.clear()
    _ic.unregister_all()
    RunPaths.remove_tree(_root)


func _store() -> EditStore:
    return _s.manager.store

static func _f32(x: float) -> float:
    return PackedFloat32Array([x])[0]

# Every lattice point of the box from `lo`, `n` per axis, as the store samples it.
func _lattice_samples(lo: Vector3i, n: int) -> Dictionary:
    var out := {}
    for x in n:
        for y in n:
            for z in n:
                var p := lo + Vector3i(x, y, z)
                out[p] = _store().sample(Vector3(p))
    return out

static func _surface_at(x: float, z: float) -> float:
    return EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)

# A cell well away from the player, just under the surface there.
func _far_cell() -> Vector3i:
    return Vector3i(130, floori(_surface_at(130.5, 130.5)) - 1, 130)


func _assert_one_instrument_event(what: String) -> void:
    assert_eq(_log.sources(), [EditSource.Kind.INSTRUMENT] as Array[EditSource.Kind],
        "%s: one matter-changed event, credited to INSTRUMENT" % what)


# --- setcorners ---

func test_setcorners_writes_exactly_the_eight_corners() -> void:
    var cell   := _far_cell()
    var typed  := ["-0.41941944509744644", "0.3", "-1.5", "2", "0.25", "-0.75", "1e-3", "-0.0"]
    var before := _lattice_samples(cell - Vector3i.ONE, 4)
    _ic.setcorners("%d %d %d %s" % [cell.x, cell.y, cell.z, " ".join(typed)])

    _assert_one_instrument_event("setcorners")
    assert_eq(_heard.size(), 1, "the recorder hears it")
    assert_true(_heard[0][1], "as valid")
    for k in 8:
        var point := cell + Vector3i(CubeGeometry.corner(k))
        assert_eq(_store().sample(Vector3(point)), _f32(ExactDecimal.parse(typed[k])),
            "corner %d holds the typed value, to float32" % k)
        before.erase(point)
    for point: Vector3i in before:
        var now := _store().sample(Vector3(point))
        assert_true(now == before[point] or now == _f32(before[point]),
            "lattice point %s keeps its value: %s -> %s" % [point, before[point], now])
    assert_false(_s.player.flying, "a write away from the player leaves them walking")


func test_setcorners_refuses_what_it_cannot_write() -> void:
    var cell := _far_cell()
    _ic.setcorners("%d %d %d 1 2 3" % [cell.x, cell.y, cell.z])
    _ic.setcorners("%d.5 %d %d 1 1 1 1 1 1 1 1" % [cell.x, cell.y, cell.z])
    _ic.setcorners("%d %d %d 1 1 1 one 1 1 1 1" % [cell.x, cell.y, cell.z])
    assert_eq(_heard.size(), 0, "a malformed command builds no action")

    var held := PackedStringArray()
    for k in 8:
        held.append(ExactDecimal.format(_store().sample(Vector3(cell + Vector3i(CubeGeometry.corner(k))))))
    _ic.setcorners("%d %d %d %s" % [cell.x, cell.y, cell.z, " ".join(held)])
    assert_eq(_heard.size(), 1, "the recorder hears a refused write too")
    assert_false(_heard[0][1], "as refused: the corners already hold those values")
    assert_eq(_log.events.size(), 0, "and nothing is written")


# --- setmaterial ---

func test_setmaterial_paints_the_cell_and_keeps_the_field() -> void:
    var cell   := _far_cell()
    var before := _lattice_samples(cell - Vector3i.ONE, 3)
    var before_mats := _materials_around(cell)
    assert_ne(TerrainProbe.material(_store(), cell), MaterialPalette.index_of(&"Wood"), "precondition")
    _ic.setmaterial("%d %d %d wood" % [cell.x, cell.y, cell.z])

    _assert_one_instrument_event("setmaterial")
    assert_eq(TerrainProbe.material(_store(), cell), MaterialPalette.index_of(&"Wood"), "the cell is wood")
    for point: Vector3i in before:
        var now := _store().sample(Vector3(point))
        assert_true(now == before[point] or now == _f32(before[point]),
            "lattice point %s keeps its value: %s -> %s" % [point, before[point], now])

    var after_mats := _materials_around(cell)
    for near: Vector3i in before_mats:
        if near != cell:
            assert_eq(after_mats[near], before_mats[near], "neighbour %s keeps its material" % near)

    _ic.setmaterial("%d %d %d Wood" % [cell.x, cell.y, cell.z])
    assert_false(_heard.back()[1], "painting it wood again is refused")
    _ic.setmaterial("%d %d %d cheese" % [cell.x, cell.y, cell.z])
    assert_eq(_heard.size(), 2, "an unknown material builds no action")

    var air := cell + Vector3i(0, 6, 0)
    assert_false(TerrainProbe.sdf(_store(), air) < 0.0, "precondition: an air cell")
    _ic.setmaterial("%d %d %d wood" % [air.x, air.y, air.z])
    assert_eq(TerrainProbe.material(_store(), air), MaterialPalette.index_of(&"Wood"), "an air cell is painted too")

# The material of each of the 27 cells around `cell`.
func _materials_around(cell: Vector3i) -> Dictionary:
    var out := {}
    for x in 3:
        for y in 3:
            for z in 3:
                var near := cell + Vector3i(x - 1, y - 1, z - 1)
                out[near] = TerrainProbe.material(_store(), near)
    return out


# --- stamp ---

# The same stamp as the CSG tool's write, from the numbers as typed: VoxelImprint on a second world
# with the transform built from the exact decimals leaves the same store.
func test_stamp_writes_the_typed_shape() -> void:
    assert_ne(MISREAD.to_float(), ExactDecimal.parse(MISREAD), "precondition: the engine misreads it")
    var at := Vector3(ExactDecimal.parse(MISREAD), -40.25, 130.5)
    _ic.stamp("box add metal %s -40.25 130.5 2 3.5 4 0 30 -15" % MISREAD)
    _assert_one_instrument_event("stamp")
    var step := StepRegistry.step_of(_heard[0][0])
    assert_eq(step["xform"]["origin"][0], at.x, "the position is the typed decimal's double")
    var stamped := _store().serialize()

    var expected := EditStoreManager.new()
    expected.setup()
    VoxelImprint.apply(expected.store, EditSource.Kind.INSTRUMENT, &"Metal", CsgBoxShape.new(Vector3(2.0, 3.5, 4.0)),
        Transform3D(VoxelUtils.euler_basis(Vector3(0.0, 30.0, -15.0)), at), CsgState.Op.ADD)
    assert_eq(stamped, expected.store.serialize(), "the store is the typed shape's imprint")

# Each shape, unrotated and rotated, is built from its own dims count; the rotation, when typed, is
# the last three numbers.
func test_stamp_reads_each_shape_with_and_without_rotation() -> void:
    var cmds := [
        ["box add stone %d %d 130.5 1 2 1.5",            Vector3.ZERO,             [1.0, 2.0, 1.5]],
        ["box add stone %d %d 130.5 1 2 1.5 10 20 30",   Vector3(10.0, 20.0, 30.0), [1.0, 2.0, 1.5]],
        ["cylinder add sand %d %d 130.5 1.5 3",          Vector3.ZERO,             [1.5, 3.0]],
        ["cylinder add sand %d %d 130.5 1.5 3 90 0 0",   Vector3(90.0, 0.0, 0.0),  [1.5, 3.0]],
        ["sphere add wood %d %d 130.5 2",                Vector3.ZERO,             [2.0]],
        ["sphere add wood %d %d 130.5 2 0 45 0",         Vector3(0.0, 45.0, 0.0),  [2.0]],
    ]
    for i in cmds.size():
        var x := 160 + 8 * i
        _ic.stamp(cmds[i][0] % [x, floori(_surface_at(x + 0.5, 130.5)) + 1])
        assert_eq(_heard.size(), i + 1, "\"%s\" builds a stamp" % cmds[i][0])
        assert_true(_heard[i][1], "and writes: %s" % _heard[i][0].refusal())
        var action: StampAction = _heard[i][0]
        assert_eq(action.xform.basis, VoxelUtils.euler_basis(cmds[i][1]), "with rotation %s" % cmds[i][1])
        assert_eq(StepRegistry.step_of(action)["dims"], cmds[i][2], "and dims %s" % [cmds[i][2]])

    var y := _far_cell().y
    _ic.stamp("box add stone 130.5 %d 130.5 1 1" % y)
    _ic.stamp("pyramid add stone 130.5 %d 130.5 1" % y)
    assert_eq(_heard.size(), cmds.size(), "a wrong dims count or an unknown shape builds no stamp")
    _ic.stamp("box add stone 130.5 %d 130.5 0 1 1" % y)
    assert_false(_heard.back()[1], "a zero-size box is refused")


func test_stamp_refuses_a_span_past_the_cap() -> void:
    var y    := _far_cell().y
    var cap  := int(StampAction.MAX_SPAN)
    _ic.stamp("box add stone 130.5 %d 130.5 %d 1 1" % [y, cap + 2])
    assert_eq(_heard.size(), 1, "the recorder hears it")
    assert_false(_heard[0][1], "as refused")
    assert_string_contains(_heard[0][0].refusal(), "per axis", "for its span")
    assert_eq(_log.events.size(), 0, "and nothing is written")

    _ic.stamp("box add stone 130.5 %d 130.5 %d 1 1" % [y, cap - 4])
    assert_true(_heard[1][1], "a stamp inside the cap writes")


# The console's own dispatcher (LimboConsole joins a multi-word tail into a command's one String
# parameter) reaches the instruments with every word, and the decimals untouched.
func test_the_console_dispatches_instrument_commands() -> void:
    _ic.register_all()
    for name in ["setcorners", "setmaterial", "stamp", "save", "load"]:
        assert_true(LimboConsole.has_command(name), "registered: %s" % name)

    var cell := _far_cell()
    LimboConsole.execute_command("setcorners %d %d %d -1 0.5 0.5 0.5 0.5 0.5 0.5 0.25" % [cell.x, cell.y, cell.z], true)
    assert_eq(_heard.size(), 1, "setcorners ran")
    assert_eq(_store().sample(Vector3(cell)), -1.0, "with its corners")
    LimboConsole.execute_command("stamp box add metal %s %d 130.5 2 2 2 0 30 0" % [MISREAD, cell.y + 3], true)
    assert_eq(_heard.size(), 2, "stamp ran")
    assert_eq(_heard[1][0].xform.origin.x, ExactDecimal.parse(MISREAD), "with the typed decimal's double")

    _ic.unregister_all()
    for name in ["setcorners", "setmaterial", "stamp", "save", "load"]:
        assert_false(LimboConsole.has_command(name), "unregistered: %s" % name)


# --- Fly mode: only when the player-safety check says so ---

func test_removing_the_ground_under_the_player_makes_them_fly() -> void:
    var cell := Vector3i(100, floori(_surface) - 1, 100)
    var air  := SetCornersAction.new(cell, PackedFloat64Array([2, 2, 2, 2, 2, 2, 2, 2]), _s.context())
    assert_eq(air.danger_of(air.written_field(), _store()), PlayerSafeAction.Danger.DROPS,
        "precondition: this write drops the player")
    assert_true(air.endangered_by(air.written_field(), _store()), "precondition: a player edit writing it is refused")

    _ic.setcorners("%d %d %d 2 2 2 2 2 2 2 2" % [cell.x, cell.y, cell.z])
    _assert_one_instrument_event("the write under the player")
    assert_true(_s.player.flying, "the player flies")
    assert_false(_s.player.noclip, "with collision: nothing is in them")


func test_burying_the_player_makes_them_fly_through_it() -> void:
    var at := _s.player.global_position
    _ic.stamp("sphere add stone %s %s %s 1" % [ExactDecimal.format(at.x), ExactDecimal.format(at.y), ExactDecimal.format(at.z)])
    _assert_one_instrument_event("the stamp on the player")
    assert_true(_s.player.flying, "the player flies")
    assert_true(_s.player.noclip, "through the stone they're in")


# --- Steps ---

# Recorded as a click is (RecordingCommands: validated -> ScenarioRecorder.action), the writes
# replay to the same store.
func test_recorded_instrument_writes_replay_to_the_same_world() -> void:
    var r := ScenarioRecorder.new()
    assert_true(r.start_fresh(_dir, _s.frame), "the recording starts: %s" % r.error)
    _ic.validated.connect(func(action: Action, valid: bool) -> void:
        assert_true(r.action(action, valid, _s.player.global_position, _s.frame), "recorded: %s" % r.error))

    var cell := _far_cell()
    _ic.setcorners("%d %d %d -1 -1 -1 -1 0.5 0.5 0.5 %s" % [cell.x, cell.y, cell.z, MISREAD])
    _s.advance(3)
    _ic.setmaterial("%d %d %d metal" % [cell.x, cell.y + 1, cell.z])
    _ic.stamp("cylinder subtract stone 130.25 %d 129.75 1.5 2 0 0 %s" % [cell.y, MISREAD])
    _ic.setmaterial("%d %d %d metal" % [cell.x, cell.y + 1, cell.z])
    _s.settle()
    assert_true(r.stop(_s.frame), "the recording stops: %s" % r.error)
    assert_eq(r.steps.map(func(st: Dictionary) -> String: return st["op"]),
        ["player_at", "set_corners", "advance", "set_material", "stamp", "set_material", "advance"])
    var live := _s.capture()

    _s.free()
    _s = Scenario.new()
    add_child(_s)
    _live = [_s]
    assert_true(_s.run_recording(_dir), "the recording replays: %s" % _s.error)
    assert_eq(_s.capture(), live, "to the same world")


func test_the_builder_writes_instrument_steps() -> void:
    var cell := _far_cell()
    _s.player_at(_s.player.global_position)
    assert_true(_s.set_corners(cell, PackedFloat64Array([-1, -1, -1, -1, 1, 1, 1, 1])), "set_corners runs")
    assert_true(_s.set_material(cell, &"Sand"), "set_material runs")
    assert_true(_s.stamp(CsgSphereShape.new(1.25), Transform3D(Basis(), Vector3(cell) + Vector3.UP * 3.0),
        CsgState.Op.ADD, &"Wood"), "stamp runs")
    assert_eq(_log.sources(), [EditSource.Kind.REPLAY, EditSource.Kind.REPLAY, EditSource.Kind.REPLAY] as Array[EditSource.Kind],
        "a scenario's writes are credited to the replay")
    var text := _s.write()
    var live := _s.capture()

    _s.free()
    _s = Scenario.new()
    add_child(_s)
    _live = [_s]
    _s.start_fresh()
    assert_true(_s.replay(text), "the file replays: %s" % _s.error)
    assert_eq(_s.capture(), live, "to the same world")


# --- The probe ---

func test_the_probe_reports_corners_and_the_mesher_sign_test() -> void:
    var cell := _far_cell()
    var probe := ProbeAction.new(Vector3(cell) + Vector3(0.5, 0.5, 0.5), Vector3.ZERO, Vector3.ZERO, _s.context())
    assert_eq(probe.target_cell(), cell, "precondition: the probe aims at the cell")
    var root := "  leaf     unedited (the generator's), %s m at %s" % [ProbeAction._num(EditStoreManager.ROOT_SIZE),
        ProbeAction._vec(EditStoreManager.ROOT_ORIGIN)]
    assert_true(Array(probe.report()).has(root),
        "before: the generator's root: %s" % [probe.report()])

    _ic.setcorners("%d %d %d -1 0.5 0.5 0.5 0.5 0.5 0.5 0.25" % [cell.x, cell.y, cell.z])
    var lines := Array(probe.report())
    assert_true(lines.has("  leaf     edited, its own field, 1 m at (%d, %d, %d)" % [cell.x, cell.y, cell.z]),
        "after: the store's 1 m leaf: %s" % [lines])
    assert_true(lines.has("  corners  z=0  -1.0000   0.5000   0.5000   0.5000"), "the z=0 corners: %s" % [lines])
    assert_true(lines.has("           z=1   0.5000   0.5000   0.5000   0.2500"), "the z=1 corners")
    assert_true(lines.has("  sign     1/8 solid, 3/12 edges cross: the mesher puts a surface here"),
        "one solid corner: its three edges cross")

    _ic.setcorners("%d %d %d -1 -1 -1 -1 -1 -1 -1 -0.5" % [cell.x, cell.y, cell.z])
    assert_true(Array(probe.report()).has("  sign     8/8 solid, 0/12 edges cross: no surface for the mesher"),
        "all solid: no crossing")


# A cell inside a 2 m edited leaf whose +x face meets a 1 m leaf holding other values: the mesher
# reads that face's corners from the 1 m leaf (the upper side), the cell's own leaf trilerps its own.
func test_the_probe_reports_a_seam_between_disagreeing_leaves() -> void:
    var o := Vector3i(128, -64, 128)
    var paint := PackedByteArray([2, 2, 2, 2, 2, 2, 2, 2])
    _store().write_region(_filled(8, -1.0), paint, 2, Vector3(o), 2.0)
    _store().write_region(_filled(8, 1.0), paint, 2, Vector3(o + Vector3i(2, 0, 0)), 1.0)

    var inner := Array(_probe_at(o).report())
    assert_eq(inner.filter(func(l: String) -> bool: return l.begins_with("  seam")), [],
        "a cell whose corners are all its own leaf's has no seam: %s" % [inner])
    var edge := Array(_probe_at(o + Vector3i(1, 0, 0)).report())
    assert_true(edge.has("  seam     corner 1: this cell's leaf holds -1.0000"),
        "corner 1 lies on the 1 m leaf, which holds +1: %s" % [edge])

# A 1 m write in a 2 m edited leaf subdivides it: the probe names the inherited 1 m leaf beside the
# write and the 2 m leaf whose field it reads.
func test_the_probe_reports_an_inherited_leaf_and_its_source() -> void:
    var o := Vector3i(128, -64, 128)
    var paint := PackedByteArray([2])
    _store().write_region(_filled(8, -1.0), paint, 2, Vector3(o), 2.0)
    _store().write_region(_filled(8, 1.0), paint, 2, Vector3(o), 1.0)

    var lines := Array(_probe_at(o + Vector3i(1, 0, 0)).report())
    assert_true(lines.has("  leaf     edited, inherited, 1 m at (129, -64, 128)"), "the inherited leaf: %s" % [lines])
    assert_true(lines.has("           from the 2 m leaf at (128, -64, 128)"), "and its source")
    assert_true(Array(_probe_at(o).report()).has("  leaf     edited, its own field, 1 m at (128, -64, 128)"),
        "the written leaf holds its own field")

func _probe_at(cell: Vector3i) -> ProbeAction:
    return ProbeAction.new(Vector3(cell) + Vector3(0.5, 0.5, 0.5), Vector3.ZERO, Vector3.ZERO, _s.context())

static func _filled(n: int, v: float) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(n)
    out.fill(v)
    return out


# --- Named saves ---

const SLOT := "test_instruments_slot"

func _default_slot_files() -> Array:
    return [SaveSlot.snapshot_path(SaveSlot.DEFAULT), SaveSlot.editstore_path(SaveSlot.DEFAULT)].map(
        func(p: String) -> Variant: return FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else null)

func test_a_named_save_round_trips_and_leaves_the_default_slot_alone() -> void:
    var default_before := _default_slot_files()
    _s.set_corners(_far_cell(), PackedFloat64Array([-1, -1, -1, -1, 1, 1, 1, 1]))
    _s.settle()
    assert_eq(SaveSlot.save(SLOT, _s, _s.manager), "", "the named save writes")
    var live := _s.capture()
    assert_eq(_default_slot_files(), default_before, "the default slot is untouched")

    assert_eq(SaveSlot.request_load(SLOT), "", "the slot loads")
    assert_eq(SaveSlot.take_pending_load(), SLOT, "the next World load reads it")
    assert_eq(SaveSlot.take_pending_load(), SaveSlot.DEFAULT, "once")

    _s.free()
    _s = Scenario.new()
    add_child(_s)
    _live = [_s]
    assert_true(_s.start_save(SaveSlot.snapshot_path(SLOT), SaveSlot.editstore_path(SLOT)), "loads: %s" % _s.error)
    assert_eq(_s.capture(), live, "to the same world")
    RunPaths.remove_tree(SaveSlot.dir_of(SLOT))

func test_slot_names_and_missing_slots_are_refused() -> void:
    for name in ["..", ".hidden", "a/b", "c:d", "world.snapshot", "world.editstore", "world.snapshot.tmp", "world.editstore.tmp"]:
        assert_false(SaveSlot.is_valid(name), "\"%s\" is no slot" % name)
        assert_ne(SaveSlot.save(name, _s, _s.manager), "", "\"%s\" isn't saved to" % name)
    assert_ne(SaveSlot.request_load("no_such_slot"), "", "a slot never saved doesn't load")
    assert_eq(SaveSlot.take_pending_load(), SaveSlot.DEFAULT, "and isn't pending")
