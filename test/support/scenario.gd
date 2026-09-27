extends "res://test/support/world_stub.gd"

# Doc 22's replay runner and scenario builder (the record -> test loop, step 4): a world without the
# World scene. The real EditStore, TerrainSupport, PartIndex, MpmStructure and DetachmentScout, wired
# as world.gd wires them, and the save's player stub, moved only by player_at steps.
#
# Time is the runner's. Processing is disabled for the whole subtree, so no simulation ticks on
# wall-clock frames; advance() and settle() step them one physics frame at a time, 1/TICK_RATE s,
# in the live frame's order (_tick).
#
# The builder and the replay are one path. A builder call writes its step, reads that step back from
# its own JSON text, and runs what it read, exactly as a replay runs a line of a step file; an
# action step records what validate() returned as "expect_valid". A replay stops at the first step
# that doesn't run as recorded (validate() disagrees, or the step is malformed or can't settle) and
# names its index; nothing after it runs.
#
# Usage: add the node to the tree, then start_fresh() or start_save(), or run_recording() for a
# directory ScenarioRecorder wrote. The event bus is global and its events carry no world, so a
# second live scenario would hear the first's edits: one is live at a time, and a test free()s one
# before starting the next (queue_free is too late).
# docs/roadmap/design/22-scenario-languages.md.
# (Drafted by Claude, overnight 2026-09-27.)

const TICK_RATE          := 60
const SETTLE_FRAME_LIMIT := 36000   # ten game minutes; past it the world isn't coming to rest

static var _live: WeakRef = null

var manager:   EditStoreManager
var integrity: StructuralIntegrity
var player:    CharacterBody3D
var mpm:       MpmStructure
var scout:     DetachmentScout

var steps: Array[Dictionary] = []   # every step that ran, as a step file writes it
var marks: Array[Dictionary] = []   # {step, frame, note, capture}; step indexes `steps`
var frame: int               = 0    # physics frames advanced since the start

var error:      String = ""   # why the scenario stopped; "" while it runs
var stopped_at: int    = -1   # the step that didn't run (replay()'s file index); -1 when none did

var settle_frame_limit := SETTLE_FRAME_LIMIT

var _ctx: ActionContext


# --- Starting ---

# The generator's world, unedited.
func start_fresh() -> bool:
    if not _claim():
        return false

    _wire()
    return true


# The world a save pair holds: field, tracked voxels with their support, part identity and the
# player. The snapshot also restores the terrain shader's tunables, as a load in the game does.
func start_save(snapshot_path: String, editstore_path: String) -> bool:
    if not _claim():
        return false

    var saved := SavedWorld.read(snapshot_path, editstore_path)
    if not saved.load_into(self, manager):
        return _stop(-1, "the save didn't load: %s" % (saved.refusal if saved.refusal != "" else "there is none"))

    _wire()
    return true


func _claim() -> bool:
    var other: Object = _live.get_ref() if _live != null else null
    if other != null and other != self:
        return _stop(-1, "another scenario is live, and it would hear this one's events")
    if manager != null:
        return _stop(-1, "already started")
    if not is_inside_tree():
        return _stop(-1, "not in the tree, so StructuralIntegrity isn't ready")

    _live   = weakref(self)
    manager = EditStoreManager.new()
    manager.setup()
    return true


# In world.gd's order: the store (restored), support, then MPM and the scout, then world-ready.
func _wire() -> void:
    process_mode = Node.PROCESS_MODE_DISABLED
    integrity    = get_node("StructuralIntegrity")
    player       = get_node("Player")
    integrity.set_store(manager.store)

    mpm = MpmStructure.new()
    add_child(mpm)
    mpm.setup(manager.store)
    integrity.mpm = mpm

    scout = DetachmentScout.new()
    add_child(scout)
    scout.setup(manager.store, integrity)

    _ctx = ActionContext.new(manager.store, player, integrity, EditSource.Kind.REPLAY)
    VoxelEventBusSingleton.emit(WorldReadyEvent.CHANNEL, WorldReadyEvent.new())


# A ScenarioRecorder directory, start to finish: from its save pair when it has one (either half
# present means a pair was meant; start_save refuses a lone half), otherwise fresh.
func run_recording(dir: String) -> bool:
    var snapshot  := "%s/%s" % [dir, ScenarioRecorder.SNAPSHOT_FILE]
    var editstore := "%s/%s" % [dir, ScenarioRecorder.EDITSTORE_FILE]
    var from_save := FileAccess.file_exists(snapshot) or FileAccess.file_exists(editstore)
    if not (start_save(snapshot, editstore) if from_save else start_fresh()):
        return false

    var text := FileAccess.get_file_as_string("%s/%s" % [dir, ScenarioRecorder.STEPS_FILE])
    if text.is_empty():
        return _stop(-1, "%s has no %s" % [dir, ScenarioRecorder.STEPS_FILE])
    return replay(text)


# --- The builder ---

# Each runs its step and records it; an action's returns what validate() said. A builder step that
# can't run is a mistake in the test, so it's an error, not a result to inspect.
func player_at(position: Vector3) -> void:
    _record(StepRegistry.player_at(position))

func advance(frames: int) -> void:
    _record(StepRegistry.advance(frames))

func settle() -> void:
    _record(StepRegistry.settle())

func mark(note: String) -> void:
    _record(StepRegistry.mark(note))

func thaw(center: Vector3, radius: float) -> void:
    _record(StepRegistry.thaw(center, radius))

func dig(position: Vector3, radius: float) -> bool:
    return act(DigAction.new(position, radius, _ctx))

func fill(position: Vector3, radius: float, material: StringName) -> bool:
    return act(FillAction.new(position, radius, _ctx, material))

func flatten(plane_point: Vector3, normal: Vector3, radius: float) -> bool:
    return act(FlattenAction.new(plane_point, normal, radius, _ctx))

func raise(position: Vector3, radius: float) -> bool:
    return act(RaiseAction.new(position, radius, _ctx))

func lower(position: Vector3, radius: float) -> bool:
    return act(LowerAction.new(position, radius, _ctx))

func fill_voxel(cell: Vector3i, material: StringName) -> bool:
    return act(FillVoxelAction.new(cell, _ctx, material))

func empty_voxel(cell: Vector3i) -> bool:
    return act(EmptyVoxelAction.new(cell, _ctx))

func csg(shape: CsgShape, xform: Transform3D, mode: CsgState.Op, material: StringName) -> bool:
    return act(CsgAction.new(shape, xform, mode, material, _ctx))

func build(part: Part, position: Vector3, rotation: Vector3, material: StringName) -> bool:
    return act(ConstructionAction.new(part, position, rotation, material, _ctx))

func probe(hit_pos: Vector3, hit_normal: Vector3, offset: Vector3) -> bool:
    return act(ProbeAction.new(hit_pos, hit_normal, offset, _ctx))

# The instruments (InstrumentCommands' writes). A replay only moves the player by player_at, so
# the fly mode a live instrument write may switch on isn't a step.
func set_corners(cell: Vector3i, corners: PackedFloat64Array) -> bool:
    return act(SetCornersAction.new(cell, corners, _ctx))

func set_material(cell: Vector3i, material: StringName) -> bool:
    return act(SetMaterialAction.new(cell, material, _ctx))

func stamp(shape: CsgShape, xform: Transform3D, mode: CsgState.Op, material: StringName) -> bool:
    return act(StampAction.new(shape, xform, mode, material, _ctx))

# Any action built in context(): recorded as its step, then that step is what runs.
func act(action: Action) -> bool:
    return _record(StepRegistry.step_of(action)) and steps.back()["expect_valid"]

# Where a builder action is built: this world's store and player, its edits credited to REPLAY.
func context() -> ActionContext:
    return _ctx

# World's accessor, which the game's ActionFactories resolves the store through.
func edit_store_ref() -> EditStore:
    return manager.store


func _record(step: Dictionary) -> bool:
    if manager == null and error == "":
        _stop(-1, "not started")
    if error != "":
        push_error("Scenario: stopped (%s); nothing more runs" % error)
        return false

    var sj   := StepJson.new()
    var text := sj.stringify(step)
    if sj.error == "":
        sj.parse(text)

    if sj.error != "":
        _stop(steps.size(), sj.error)
    elif _run(sj.data, steps.size(), true):
        return true

    push_error("Scenario: %s" % error)
    return false


# --- The step file ---

# Every step that ran, as a step file.
func write() -> String:
    var doc := StepDocument.new()
    doc.steps = steps
    var text := doc.write()
    if doc.error != "":
        push_error("Scenario: %s" % doc.error)
    return text


# Runs a step file's steps in order. False at the first that doesn't run as recorded: `stopped_at`
# is its index in this file (a builder step's is its index in `steps`) and `error` says why. A file
# this build won't read runs nothing.
func replay(text: String) -> bool:
    if manager == null and error == "":
        return _stop(-1, "not started")
    if error != "":
        return false

    var doc := StepDocument.new()
    if not doc.read(text):
        return _stop(-1, doc.error)

    for i in doc.steps.size():
        if not _run(doc.steps[i], i, false):
            return false
    return true


# --- Running a step ---

func _run(step: Dictionary, step_index: int, recording: bool) -> bool:
    var fields := StepFields.new(step)
    var op     := fields.text("op")
    var handler: Callable = _world_ops().get(op, Callable())
    var problem: String   = fields.error
    if problem == "" and not handler.is_valid() and not StepRegistry.ops().has(op):
        problem = "op: \"%s\" is not a step" % op
    if problem == "":
        problem = handler.call(fields) if handler.is_valid() else _run_action(fields, step, recording)
    if problem != "":
        return _stop(step_index, problem)

    steps.append(step)
    return true


func _world_ops() -> Dictionary:
    return {
        "player_at":     _player_at_step,
        "advance":       _advance_step,
        "settle":        _settle_step,
        "mark":          _mark_step,
        "thaw":          _thaw_step,
        "drain_support": _drain_support_step,
    }


# Recording, the step gains what validate() said; replaying, it must say the same, or the step
# stops the replay unexecuted.
func _run_action(f: StepFields, step: Dictionary, recording: bool) -> String:
    var expected := false if recording else f.flag("expect_valid")
    var action   := StepRegistry.action_of(f, _ctx)
    if action == null:
        return f.error

    var valid := action.validate()
    if not recording and valid != expected:
        return "validate() is %s; the recording says %s" % [valid, expected]

    if valid:
        action.execute()
    step["expect_valid"] = valid
    return ""


func _player_at_step(f: StepFields) -> String:
    var at := f.vec3("position")
    if not _decoded(f):
        return f.error

    player.global_position = at
    return ""


func _advance_step(f: StepFields) -> String:
    var frames := f.count("frames")
    if not _decoded(f):
        return f.error

    for _i in frames:
        _tick()
    return ""


# Frame by frame until nothing structural is in flight (the save gate): the same frames the game
# would take, not a fast-forward.
func _settle_step(f: StepFields) -> String:
    if not _decoded(f):
        return f.error

    var start := frame
    while not integrity.is_quiescent():
        if frame - start >= settle_frame_limit:
            return "not settled after %d frames" % settle_frame_limit
        _tick()
    return ""


# A recorded mark names the file holding what the view was (ScenarioRecorder.save_capture).
func _mark_step(f: StepFields) -> String:
    var note    := f.text("note")
    var capture := f.text("capture") if f.has("capture") else ""
    if not _decoded(f):
        return f.error

    marks.append({"step": steps.size(), "frame": frame, "note": note, "capture": capture})
    return ""


func _thaw_step(f: StepFields) -> String:
    var center := f.vec3("center")
    var radius := f.number("radius")
    if not _decoded(f):
        return f.error

    mpm.thaw_sphere(center, radius, EditSource.Kind.REPLAY)
    return ""


# Deterministic, and it may leave support unsettled exactly as it did live, so it can't fail a replay.
func _drain_support_step(f: StepFields) -> String:
    if not _decoded(f):
        return f.error

    integrity.force_quiescent()
    return ""


func _decoded(f: StepFields) -> bool:
    f.check_all_read()
    return f.error == ""


# One physics frame, in the live order: world.tscn has StructuralIntegrity before the MPM and scout
# nodes world.gd appends, and a frame runs _physics_process in tree order. The player's clicks
# arrive as input, ahead of the frame, which is where a step's action lands too.
func _tick() -> void:
    integrity.tick()
    mpm.tick(1.0 / TICK_RATE)
    scout.tick()
    frame += 1


func _stop(step_index: int, problem: String) -> bool:
    stopped_at = step_index
    error      = problem if step_index < 0 else "step %d: %s" % [step_index, problem]
    return false


# --- Comparing worlds ---

# Everything a replay must reproduce, as bytes: the field, part identity, the tracked voxels in the
# order they were tracked, the material MPM has in flight, and where the player stands.
func capture() -> Dictionary:
    return {
        "store":  manager.store.serialize(),
        "parts":  var_to_bytes(index.encode()),
        "voxels": var_to_bytes(_tracked_voxels()),
        "mpm":    var_to_bytes(mpm.particle_positions()),
        "player": var_to_bytes(player.global_position),
    }

func _tracked_voxels() -> Array:
    var out: Array = []
    var data := integrity.terrain_support.voxel_data
    for pos in data:
        out.append([pos, data[pos].material.name, data[pos].support, data[pos].dirty])
    return out
