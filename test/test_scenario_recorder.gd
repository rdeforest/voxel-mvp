extends GutTest

# The recorder (ScenarioRecorder): fed what a live game feeds it (each action at its validate(), the
# console's thaw and settle, marks), on a runner world standing in for the live one, it writes a
# directory the runner replays to the same world, byte for byte, in the same frames.
# docs/roadmap/design/22-scenario-languages.md, the record -> test loop.
# (Drafted by Claude, overnight 2026-09-27.)

const Scenario := preload("res://test/support/scenario.gd")
const RunPaths := preload("res://test/support/run_paths.gd")

const FOOT   := Vector3(100.5, -45.0, 100.5)
const PLAYER := Vector3(106.5, -40.0, 100.5)

var _root: String      = RunPaths.path("test_scenario_recorder")
var _dir:  String      = _root + "/take"
var _live: Array[Node] = []


func after_each() -> void:
    for s in _live:
        if is_instance_valid(s):
            s.free()
    _live.clear()
    RunPaths.remove_tree(_root)


# In the tree and not yet started; the previous one is freed first, since the bus is global.
func _scenario() -> Scenario:
    for s in _live:
        if is_instance_valid(s):
            s.free()
    var s := Scenario.new()
    add_child(s)
    _live = [s]
    return s

func _fresh() -> Scenario:
    var s := _scenario()
    assert_true(s.start_fresh(), "the scenario starts: %s" % s.error)
    return s


# --- The live game, played on a runner world ---

# player.gd's click: validate, tell the recorder, execute.
func _click(s: Scenario, r: ScenarioRecorder, action: Action) -> bool:
    var valid := action.validate()
    assert_true(r.action(action, valid, s.player.global_position, s.frame), "recorded: %s" % r.error)
    if valid:
        action.execute()
    return valid

# The console's `mpmthaw`.
func _thaw(s: Scenario, r: ScenarioRecorder, center: Vector3, radius: float) -> void:
    assert_true(r.thaw(center, radius, s.frame), "recorded: %s" % r.error)
    s.mpm.thaw_sphere(center, radius, EditSource.Kind.INSTRUMENT)

# The console's `settle`.
func _drain(s: Scenario, r: ScenarioRecorder) -> void:
    assert_true(r.drain_support(s.frame), "recorded: %s" % r.error)
    s.integrity.force_quiescent()


# A pillar under a beam, then play at uneven intervals: the player moves between clicks, a fill over
# them is refused, the pillar is cut, the beam detaches and falls, a thaw and a drain land mid-flight,
# and the recording stops with MPM still busy, so the world it ends on depends on every frame.
func _play(s: Scenario, r: ScenarioRecorder) -> void:
    var ctx := s.context()
    s.player.global_position = PLAYER
    assert_true(_click(s, r, CsgAction.new(CsgBoxShape.new(Vector3(1.6, 12.0, 1.6)),
        Transform3D(Basis(), FOOT + Vector3.UP * 4.0), CsgState.Op.ADD, &"Stone", ctx)), "the pillar stands")
    s.advance(7)
    assert_true(_click(s, r, ConstructionAction.new(preload("res://assets/parts/beam/beam.tres"),
        FOOT + Vector3.UP * 10.0, Vector3.ZERO, &"Wood", ctx)), "the beam rests on it")
    s.advance(3)
    s.player.global_position = PLAYER + Vector3(0.0, 0.0, 2.0)
    assert_false(_click(s, r, FillAction.new(s.player.global_position, 1.0, ctx, &"Stone")),
        "a fill over the player is refused")
    s.settle()
    assert_true(_click(s, r, LowerAction.new(FOOT + Vector3.UP * 5.0, 3.0, ctx)), "the lower cuts the pillar")
    s.advance(12)
    _thaw(s, r, FOOT + Vector3(-5.0, -4.0, -5.0), 1.5)
    s.advance(20)
    _drain(s, r)
    assert_ne(r.mark("the beam is falling", s.frame), "", "the mark is recorded: %s" % r.error)
    s.advance(9)
    assert_false(s.integrity.is_quiescent(), "precondition: the recording ends mid-flight")
    assert_true(r.stop(s.frame), "the recording stops: %s" % r.error)


# The recording's directory and the world it ended on, from a scenario freed before this returns.
func _recorded_fresh() -> Dictionary:
    var s := _fresh()
    var r := ScenarioRecorder.new()
    assert_true(r.start_fresh(_dir, s.frame), "the recording starts: %s" % r.error)
    _play(s, r)
    return {"capture": s.capture(), "frame": s.frame, "steps": r.steps.duplicate(true)}

func _steps_file() -> String:
    return FileAccess.get_file_as_string("%s/%s" % [_dir, ScenarioRecorder.STEPS_FILE])

func _doc(text: String) -> StepDocument:
    var doc := StepDocument.new()
    assert_true(doc.read(text), "the step file reads: %s" % doc.error)
    return doc

func _ops(steps: Array) -> Array:
    return steps.map(func(st: Dictionary) -> String: return st["op"])


# --- Round trip ---

func test_a_fresh_recording_replays_to_the_same_world() -> void:
    var live := _recorded_fresh()
    assert_false(FileAccess.file_exists("%s/%s" % [_dir, ScenarioRecorder.SNAPSHOT_FILE]),
        "a fresh recording has no save pair, so a replay starts from the generator")

    var s := _scenario()
    assert_true(s.run_recording(_dir), "the directory replays: %s" % s.error)
    assert_eq(s.capture(), live["capture"], "field, parts, tracked voxels and player are byte-identical")
    assert_eq(s.frame, live["frame"], "in the same number of frames")
    assert_eq(s.marks.size(), 1, "with the mark")
    assert_eq(s.marks[0]["capture"], "mark-001.json", "naming its capture file")


func test_the_steps_are_the_play_in_order_with_its_time_and_positions() -> void:
    var steps: Array = _recorded_fresh()["steps"]
    assert_eq(_ops(steps), ["player_at", "csg", "advance", "build", "advance", "player_at", "fill", "advance",
        "lower", "advance", "thaw", "advance", "drain_support", "mark", "advance"],
        "a player_at only when the player moved; an advance only when frames passed")
    assert_eq(steps[2]["frames"], 7, "the frames between the pillar and the beam")
    assert_eq(steps[5]["position"], StepFields.encode_vec3(PLAYER + Vector3(0.0, 0.0, 2.0)), "where the player moved")
    assert_false(steps[6]["expect_valid"], "the refused fill says so")
    assert_true(steps[8]["expect_valid"], "the lower says it ran")
    assert_eq(_steps_file(), _written(steps), "steps.json is what was recorded")


# The equality above means something only if the world it ends on depends on the recorded time and
# positions: one frame fewer, one frame moved from after a step to before it, or no player_at,
# replays to a different world.
func test_the_recorded_world_depends_on_its_frames_and_positions() -> void:
    var live := _recorded_fresh()
    var doc  := _doc(_steps_file())

    var short := doc.steps.duplicate(true)
    short[9]["frames"] = short[9]["frames"] - 1
    var s := _scenario()
    s.start_fresh()
    s.replay(_written(short))
    assert_eq(s.error, "", "precondition: the shortened file replays")
    assert_ne(s.capture()["mpm"], live["capture"]["mpm"], "one frame fewer puts the falling material elsewhere")

    var shifted := doc.steps.duplicate(true)
    shifted[7]["frames"] = shifted[7]["frames"] - 1
    shifted[9]["frames"] = shifted[9]["frames"] + 1
    s = _scenario()
    s.start_fresh()
    s.replay(_written(shifted))
    assert_eq(s.frame, live["frame"], "precondition: the shifted file runs as many frames")
    assert_ne(s.capture()["mpm"], live["capture"]["mpm"], "the cut a frame early puts the falling material elsewhere")

    var unmoved := doc.steps.filter(func(st: Dictionary) -> bool: return st["op"] != "player_at")
    s = _scenario()
    s.start_fresh()
    assert_false(s.replay(_written(unmoved)), "without the player's positions the refused fill runs")

func _written(steps: Array) -> String:
    var doc := StepDocument.new()
    doc.steps.assign(steps)
    return doc.write()


# The pair is written at the start and the steps continue from it: a world with a part and tracked
# support replays from the directory to the same world.
func test_a_recording_from_a_settled_world_replays_from_its_save_pair() -> void:
    var s := _fresh()
    s.player_at(PLAYER)
    s.csg(CsgBoxShape.new(Vector3(1.6, 12.0, 1.6)), Transform3D(Basis(), FOOT + Vector3.UP * 4.0),
        CsgState.Op.ADD, &"Stone")
    s.build(preload("res://assets/parts/beam/beam.tres"), FOOT + Vector3.UP * 10.0, Vector3.ZERO, &"Wood")
    s.settle()

    var r := ScenarioRecorder.new()
    assert_true(r.start_save(_dir, s.frame, s, s.manager), "the recording starts: %s" % r.error)
    assert_true(FileAccess.file_exists("%s/%s" % [_dir, ScenarioRecorder.SNAPSHOT_FILE]), "with the snapshot")
    assert_true(FileAccess.file_exists("%s/%s" % [_dir, ScenarioRecorder.EDITSTORE_FILE]), "and the blob")
    assert_true(_click(s, r, LowerAction.new(FOOT + Vector3.UP * 5.0, 3.0, s.context())), "the lower cuts the pillar")
    s.advance(25)
    assert_true(r.stop(s.frame), "the recording stops: %s" % r.error)
    var live := s.capture()

    var replayed := _scenario()
    assert_true(replayed.run_recording(_dir), "the directory replays: %s" % replayed.error)
    assert_eq(replayed.capture(), live, "to the same world")


# A save holds no in-flight work, so a start mid-settle would replay from a different world.
func test_a_recording_waits_for_a_settled_world() -> void:
    var s := _fresh()
    s.csg(CsgBoxShape.new(Vector3(3.0, 3.0, 3.0)), Transform3D(Basis(), FOOT + Vector3.UP * 30.0),
        CsgState.Op.ADD, &"Stone")
    assert_false(s.integrity.is_quiescent(), "precondition: the floating block is still in flight")

    var r := ScenarioRecorder.new()
    assert_false(r.start_save(_dir, s.frame, s, s.manager), "refused")
    assert_string_contains(r.error, "still settling")
    assert_false(DirAccess.dir_exists_absolute(_dir), "and nothing written")


# Every action the player's tools can make has a step op: an action without one ends the recording.
func test_every_action_a_tool_makes_is_recordable() -> void:
    var s      := _fresh()
    var camera := Camera3D.new()
    var build  := BuildState.new()
    var csg    := CsgState.new()
    var af     := ActionFactories.new(s.player, s.integrity, camera, build, csg)
    for tool in ToolCatalog.new(af, build, csg).tools:
        for activity in tool.activities:
            var action: Action = activity.make_action.call(FOOT, Vector3.UP)
            assert_false(StepRegistry.step_of(action).is_empty(),
                "%s/%s's %s has a step op" % [tool.name, activity.mode_name, action.get_script().get_global_name()])
    camera.free()


# --- The directory on disk ---

# steps.json is rewritten per step, so a crash keeps a file that replays to the world as of its
# last step.
func test_a_recording_that_never_stops_still_replays() -> void:
    var s := _fresh()
    var r := ScenarioRecorder.new()
    r.start_fresh(_dir, s.frame)
    s.player.global_position = PLAYER
    s.advance(4)
    _click(s, r, DigAction.new(FOOT + Vector3.DOWN, 2.0, s.context()))
    var at_click := s.capture()
    s.advance(30)

    var replayed := _scenario()
    assert_true(replayed.run_recording(_dir), "the directory replays: %s" % replayed.error)
    assert_eq(replayed.capture(), at_click, "to the world as of the last step")
    assert_eq(replayed.frame, 4, "the frames after it weren't written")


func test_a_mark_writes_its_capture_and_screenshot() -> void:
    var s := _fresh()
    var r := ScenarioRecorder.new()
    r.start_fresh(_dir, s.frame)
    var capture := {"camera": {"fov": 75.0, "transform": StepFields.encode_xform(Transform3D.IDENTITY)}, "aim": null}
    var shot    := Image.create(8, 4, false, Image.FORMAT_RGB8)
    shot.fill(Color.RED)

    var first  := r.mark("with a picture", s.frame)
    var second := r.mark("headless", s.frame)
    assert_eq([first, second], ["mark-001", "mark-002"], "marks are numbered in order")
    assert_true(r.save_capture(first, capture, shot), "the first saves: %s" % r.error)
    assert_true(r.save_capture(second, capture, null), "the second saves without a picture: %s" % r.error)

    var sj := StepJson.new()
    assert_true(sj.parse(FileAccess.get_file_as_string(_dir + "/mark-001.json")), "the capture reads: %s" % sj.error)
    var expected := capture.duplicate()
    expected.merge({"format": "voxel-mvp/mark", "version": 1.0, "screenshot": "mark-001.png"})
    assert_eq(sj.data, expected, "the capture as given, with its header and picture")
    var png := Image.load_from_file(_dir + "/mark-001.png")
    assert_eq(png.get_size(), Vector2i(8, 4), "the picture is the screenshot")
    assert_eq(png.get_pixel(0, 0), Color.RED)

    sj.parse(FileAccess.get_file_as_string(_dir + "/mark-002.json"))
    assert_eq(sj.data["screenshot"], null, "a headless mark says it has no picture")
    assert_false(FileAccess.file_exists(_dir + "/mark-002.png"))


# --- Refusals ---

class _UnwritableStore extends EditStoreManager:
    func save_to(_path: String, _save_id: int) -> Error:
        return ERR_FILE_CANT_WRITE

# A start whose save fails leaves no directory behind, so the same name can be tried again.
func test_a_start_that_cannot_save_leaves_nothing() -> void:
    var s := _fresh()
    var r := ScenarioRecorder.new()
    assert_false(r.start_save(_dir, s.frame, s, _UnwritableStore.new()), "refused")
    assert_string_contains(r.error, "didn't save")
    assert_false(DirAccess.dir_exists_absolute(_dir), "the directory it made is gone")
    assert_true(ScenarioRecorder.new().start_save(_dir, s.frame, s, s.manager), "and the name is free again")


func test_a_recording_never_writes_over_another() -> void:
    _recorded_fresh()
    var before := _steps_file()

    var r := ScenarioRecorder.new()
    assert_false(r.start_fresh(_dir, 0), "refused")
    assert_string_contains(r.error, "already exists")
    assert_false(r.thaw(FOOT, 1.0, 0), "and it records nothing")
    assert_eq(_steps_file(), before, "the old recording is untouched")


func test_steps_out_of_time_or_after_the_stop_are_refused() -> void:
    var r := ScenarioRecorder.new()
    assert_false(r.thaw(FOOT, 1.0, 0), "before the start")
    assert_eq(r.error, "not recording")

    r = ScenarioRecorder.new()
    r.start_fresh(_dir, 10)
    assert_false(r.thaw(FOOT, 1.0, 9), "a frame before the start")
    assert_string_contains(r.error, "frame 9 is before the last step's, 10")
    assert_false(r.is_recording(), "ends the recording")

    RunPaths.remove_tree(_root)
    r = ScenarioRecorder.new()
    r.start_fresh(_dir, 10)
    r.stop(12)
    assert_false(r.drain_support(12), "a step after the stop")
    assert_eq(_ops(_doc(_steps_file()).steps), ["advance"], "the file ends at the stop")


func test_a_recording_name_is_a_plain_file_name() -> void:
    assert_eq(ScenarioRecorder.dir_for("wall-collapse"), RunPaths.path("scenarios/wall-collapse"))
    for name in ["", "a/b", "../up", "x:y"]:
        assert_eq(ScenarioRecorder.dir_for(name), "", "\"%s\" is refused" % name)


# --- The runner's side of the new steps ---

func test_a_mark_capture_that_is_not_text_stops_the_replay() -> void:
    var s := _fresh()
    assert_false(s.replay(_written([{"op": "mark", "note": "x", "capture": 3}])), "refused")
    assert_string_contains(s.error, "capture: expected a string")


func test_a_drain_step_settles_support_at_once() -> void:
    var s := _fresh()
    s.csg(CsgBoxShape.new(Vector3(1.6, 6.0, 1.6)), Transform3D(Basis(), FOOT + Vector3.UP * 2.0),
        CsgState.Op.ADD, &"Stone")
    assert_false(s.integrity.terrain_support.dirty_queue.is_empty(), "precondition: support is propagating")

    assert_true(s.replay(_written([StepRegistry.drain_support()])), "the step runs: %s" % s.error)
    assert_true(s.integrity.terrain_support.dirty_queue.is_empty(), "support drained")
    assert_eq(s.frame, 0, "without a frame passing")
