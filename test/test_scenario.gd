extends GutTest

# The replay runner and builder (test/support/scenario.gd): a hand-written step file runs; a built
# scenario round-trips through its JSON and replays to the same world, byte for byte; an altered
# step stops the replay at its index with nothing after it run; time passes only when the runner
# says; a save pair starts a scenario with its part identity and support.
# docs/roadmap/design/22-scenario-languages.md.
# (Drafted by Claude, overnight 2026-09-27.)

const Scenario := preload("res://test/support/scenario.gd")

const SNAPSHOT  := "user://test_scenario.snapshot"
const EDITSTORE := "user://test_scenario.editstore"

# A column of the game's field: ground at y = -45.9 (the scout test's fence-on-a-hill spot).
const FOOT   := Vector3(100.5, -45.0, 100.5)
const PLAYER := Vector3(106.5, -40.0, 100.5)

const HAND_WRITTEN := """{
  "format": "voxel-mvp/steps",
  "version": 1,
  "units": {"length": "meter", "angle": "degree"},
  "steps": [
    {"op": "player_at", "position": [106.5, -40.0, 100.5]},
    {"op": "dig", "position": [100.5, -46.0, 100.5], "radius": 2.5, "shape": "sphere", "expect_valid": true},
    {"op": "fill_voxel", "cell": [100, -30, 100], "material": "Wood", "expect_valid": true},
    {"op": "fill", "position": [106.5, -40.0, 100.5], "radius": 1.0, "material": "Stone", "shape": "sphere", "expect_valid": false},
    {"op": "advance", "frames": 3},
    {"op": "mark", "note": "the wood voxel hangs in the air"},
    {"op": "settle"},
    {"op": "mark", "note": "it has been detached, fallen and frozen"}
  ]
}
"""

var _live: Array[Node] = []


func after_each() -> void:
    for s in _live:
        if is_instance_valid(s):
            s.free()
    _live.clear()
    for path in [SNAPSHOT, EDITSTORE]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# In the tree and not yet started. The previous one is freed first: the bus is global.
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

func _replayed(text: String) -> Scenario:
    var s := _fresh()
    s.replay(text)
    return s


# A pillar under a beam, a dig, a refused fill (it would bury the player), then the pillar is cut:
# the scout detaches the hanging beam, MPM drops and freezes it, and the beam's record goes with it.
func _build(s: Scenario) -> void:
    s.player_at(PLAYER)
    assert_true(s.csg(CsgBoxShape.new(Vector3(1.6, 12.0, 1.6)), Transform3D(Basis(), FOOT + Vector3.UP * 4.0),
        CsgState.Op.ADD, &"Stone"), "the pillar stands")
    assert_true(s.build(preload("res://assets/parts/beam/beam.tres"), FOOT + Vector3.UP * 10.0, Vector3.ZERO, &"Wood"),
        "the beam rests on it")
    assert_true(s.dig(FOOT + Vector3(-5.0, -1.0, -5.0), 2.0), "a dig nearby")
    assert_false(s.fill(PLAYER, 1.0, &"Stone"), "a fill over the player is refused")
    s.advance(10)
    s.settle()
    s.mark("beam on pillar")
    assert_eq(s.index.count(), 1, "precondition: the beam is recorded")
    assert_true(s.lower(FOOT + Vector3.UP * 5.0, 3.0), "the lower cuts the pillar")
    s.settle()
    s.mark("beam fallen")
    s.thaw(FOOT + Vector3(-5.0, -4.0, -5.0), 1.5)
    s.settle()
    assert_eq(s.error, "", "the scenario ran to its end")


# The build's step file and final world, from a scenario freed before this returns.
func _built() -> Dictionary:
    var s := _fresh()
    _build(s)
    return {"text": s.write(), "capture": s.capture(), "frame": s.frame, "marks": s.marks.duplicate(true),
        "parts": s.index.count()}

func _doc(text: String) -> StepDocument:
    var doc := StepDocument.new()
    assert_true(doc.read(text), "the step file reads: %s" % doc.error)
    return doc

func _index_of(doc: StepDocument, op: String, nth := 0) -> int:
    var seen := 0
    for i in doc.steps.size():
        if doc.steps[i]["op"] == op:
            if seen == nth:
                return i
            seen += 1
    fail_test("no %s step #%d" % [op, nth])
    return -1

func _with_steps(steps: Array) -> String:
    var out := StepDocument.new()
    out.steps.assign(steps)
    return out.write()


# --- A hand-written scenario ---

func test_a_hand_written_scenario_runs() -> void:
    var s := _fresh()
    var store := s.manager.store
    assert_true(TerrainProbe.is_solid(store, Vector3i(100, -47, 100)), "precondition: the dig's centre is ground")

    assert_true(s.replay(HAND_WRITTEN), "the file replays: %s" % s.error)
    assert_eq(s.stopped_at, -1, "no step stopped it")
    assert_eq(s.steps.size(), 8, "every step ran")
    assert_false(TerrainProbe.is_solid(store, Vector3i(100, -47, 100)), "the dig emptied its centre")
    assert_false(TerrainProbe.is_solid(store, Vector3i(100, -30, 100)), "the floating voxel came down")
    assert_eq(s.player.global_position, Vector3(106.5, -40.0, 100.5), "the player stands where the file put them")
    assert_true(s.integrity.is_quiescent(), "settle left the world at rest")

    assert_eq(s.marks.size(), 2, "both marks")
    assert_eq(s.marks[0], {"step": 5, "frame": 3, "note": "the wood voxel hangs in the air"},
        "the first mark: its step, after three frames")
    assert_gt(s.marks[1]["frame"], 3 + MpmStructure.SETTLE_FRAMES, "settling took the fall and the freeze")


# --- Round trip ---

func test_a_built_scenario_replays_to_the_same_world() -> void:
    var built := _built()
    assert_eq(built["parts"], 0, "precondition: the fallen beam's record is gone")
    assert_gt(built["frame"], 10 + MpmStructure.SETTLE_FRAMES, "precondition: MPM ran")
    var doc := _doc(built["text"])
    assert_true(doc.steps.any(func(st: Dictionary) -> bool: return st.get("expect_valid") == false),
        "precondition: a refused step was recorded")

    var s := _replayed(built["text"])
    assert_eq(s.error, "", "the replay ran every step")
    assert_eq(s.capture(), built["capture"], "field, parts, tracked voxels and player are byte-identical")
    assert_eq(s.frame, built["frame"], "in the same number of frames")
    assert_eq(s.marks, built["marks"], "with the same marks")
    assert_eq(s.write(), built["text"], "and writes the same step file")


# --- Divergence ---

# The refused fill, moved away from the player, now validates: the replay stops at it, unexecuted.
func test_an_altered_step_stops_the_replay_at_its_index() -> void:
    var built := _built()
    var doc   := _doc(built["text"])
    var at    := _index_of(doc, "fill")
    doc.steps[at]["position"] = StepFields.encode_vec3(FOOT + Vector3.UP * 30.0)

    var s := _replayed(_with_steps(doc.steps))
    assert_eq(s.stopped_at, at, "stopped at the altered step")
    assert_string_contains(s.error, "validate() is true; the recording says false")
    assert_eq(s.steps.size(), at, "nothing from it on ran")
    var stopped := s.capture()

    var prefix := _replayed(_with_steps(doc.steps.slice(0, at)))
    assert_eq(prefix.error, "", "precondition: the steps before it replay")
    assert_eq(stopped, prefix.capture(), "the world is exactly the steps before it")


# Moving the player is a step that runs; the first step whose validate() then differs is the fill
# that no longer buries them, so that is where the replay stops.
func test_a_replay_stops_at_the_first_step_that_differs_not_at_the_cause() -> void:
    var doc := _doc(_built()["text"])
    doc.steps[_index_of(doc, "player_at")]["position"] = StepFields.encode_vec3(PLAYER + Vector3(40.0, 0.0, 0.0))

    var s := _replayed(_with_steps(doc.steps))
    assert_eq(s.stopped_at, _index_of(doc, "fill"), "stopped at the fill, not the moved player")


# The action cases replace the refused fill, so a step that skipped decoding would reach a
# validate() of false and agree with a defaulted expect_valid.
func test_a_step_that_does_not_decode_stops_the_replay() -> void:
    var doc     := _doc(_built()["text"])
    var advance := _index_of(doc, "advance")
    var fill    := _index_of(doc, "fill")
    var refused := doc.steps[fill]
    var cases := {
        "op: \"advanse\" is not a step":        [advance, {"op": "advanse", "frames": 10}],
        "op: missing":                          [advance, {"frames": 10}],
        "frames: expected a count, got 2.5":    [advance, {"op": "advance", "frames": 2.5}],
        "speed: not a field of this step":      [advance, {"op": "advance", "frames": 10, "speed": 2}],
        "expect_valid: missing":                [fill, _without(refused, "expect_valid")],
        "expect_valid: expected true or false": [fill, _with(refused, "expect_valid", "no")],
        "bogus: not a field of this step":      [fill, _with(refused, "bogus", 1)],
    }
    for message: String in cases:
        var at: int = cases[message][0]
        var steps   := doc.steps.duplicate()
        steps[at] = cases[message][1]
        var s := _replayed(_with_steps(steps))
        assert_eq(s.stopped_at, at, "%s: stopped at the step" % message)
        assert_string_contains(s.error, message)

func _with(step: Dictionary, key: String, value: Variant) -> Dictionary:
    var out := step.duplicate()
    out[key] = value
    return out

func _without(step: Dictionary, key: String) -> Dictionary:
    var out := step.duplicate()
    out.erase(key)
    return out


func test_a_world_that_does_not_settle_stops_the_replay() -> void:
    var doc := StepDocument.new()
    doc.steps = [StepRegistry.thaw(FOOT + Vector3.DOWN, 2.0), StepRegistry.settle()]
    var s := _fresh()
    s.settle_frame_limit = 5

    assert_false(s.replay(doc.write()), "the replay stops")
    assert_eq(s.stopped_at, 1, "at the settle")
    assert_string_contains(s.error, "not settled after 5 frames")


# --- Time ---

# The simulations are in the tree but never tick on the engine's frames: a floating block's
# detachment waits for advance(), however many physics frames go by.
func test_only_the_runner_advances_time() -> void:
    var s := _fresh()
    s.csg(CsgBoxShape.new(Vector3(3.0, 3.0, 3.0)), Transform3D(Basis(), FOOT + Vector3.UP * 30.0),
        CsgState.Op.ADD, &"Stone")
    assert_false(s.scout.is_idle(), "precondition: the block's edit is waiting for the scout")

    await wait_physics_frames(5)
    assert_false(s.scout.is_idle(), "engine frames didn't run the scout")
    assert_eq(s.mpm.active_count(), 0, "nor thaw anything")
    assert_eq(s.frame, 0, "the runner's clock hasn't moved")

    s.advance(5)
    assert_gt(s.mpm.active_count(), 0, "five runner frames detached the block into MPM")
    assert_eq(s.frame, 5, "and the clock moved five frames")


func test_the_tick_rate_is_the_games_physics_rate() -> void:
    assert_eq(Scenario.TICK_RATE, Engine.physics_ticks_per_second,
        "replayed frames are the game's frames; a changed physics rate needs a decision about old recordings")


func test_the_runner_runs_every_world_op() -> void:
    var s := _scenario()
    assert_eq(s._world_ops().keys(), StepRegistry.WORLD_OPS, "one vocabulary for writers and the runner")


# --- Starting from a save ---

# The continuation of a scenario, replayed from the save pair it wrote, lands on the same world, and
# the pair itself restores the part record and tracked support the field can't carry.
func test_a_scenario_starts_from_a_save_pair() -> void:
    var s := _fresh()
    s.player_at(PLAYER)
    s.csg(CsgBoxShape.new(Vector3(1.6, 12.0, 1.6)), Transform3D(Basis(), FOOT + Vector3.UP * 4.0),
        CsgState.Op.ADD, &"Stone")
    s.build(preload("res://assets/parts/beam/beam.tres"), FOOT + Vector3.UP * 10.0, Vector3.ZERO, &"Wood")
    s.settle()
    assert_eq(SavedWorld.new(SNAPSHOT, EDITSTORE).save(s, s.manager), "", "the pair saves")
    var at_save := s.capture()
    assert_gt(bytes_to_var(at_save["voxels"]).size(), 0, "precondition: support is tracked, so the pair must carry it")
    var saved_steps := s.steps.size()

    s.lower(FOOT + Vector3.UP * 5.0, 3.0)
    s.settle()
    var tail := _with_steps(s.steps.slice(saved_steps))
    var at_end := s.capture()

    var r := _scenario()
    assert_true(r.start_save(SNAPSHOT, EDITSTORE), "the scenario starts from the pair: %s" % r.error)
    assert_eq(r.index.count(), 1, "the beam's record came with it")
    assert_eq(r.capture(), at_save, "the world the pair holds, byte for byte")
    assert_true(r.replay(tail), "the continuation replays: %s" % r.error)
    assert_eq(r.capture(), at_end, "to the same world")


func test_a_scenario_that_never_started_runs_nothing() -> void:
    var s := _scenario()
    assert_false(s.replay(HAND_WRITTEN), "a replay is refused")
    assert_eq(s.error, "not started")
    assert_eq(s.steps.size(), 0, "no step ran")

    var b := _scenario()
    b.player_at(PLAYER)
    assert_eq(b.error, "not started", "and so is a builder step")
    assert_eq(b.steps.size(), 0)
    assert_push_error("not started")


func test_one_scenario_is_live_at_a_time() -> void:
    var first := _fresh()
    var second := Scenario.new()
    add_child_autofree(second)

    assert_false(second.start_fresh(), "a second live scenario is refused")
    assert_string_contains(second.error, "another scenario is live")
    assert_eq(first.error, "", "the first is untouched")
