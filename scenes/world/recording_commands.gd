class_name RecordingCommands
extends Node

# The console's `rec` and `mark`: the live game recorded as a scenario (ScenarioRecorder) that the
# replay runner plays back. What it hears: every action the player's click validated
# (Player.action_validated), every instrument write likewise (InstrumentCommands.validated), and the
# console's own world writes, `mpmthaw` and `settle` (ConsoleCommands.thawing / draining_support).
#
# The clock is this node's physics frames. It ticks exactly when the structural simulations do and
# pauses with them (an open console pauses the tree), which the engine's physics frame count doesn't.
#
# `rec fresh` resets the world, which frees this node; the directory waits in a static for the
# reloaded world's node, which starts recording on its world-ready, the frame the simulations wake.
# docs/roadmap/design/22-scenario-languages.md, the record -> test loop.
# (Drafted by Claude, overnight 2026-09-27.)

const USAGE := "usage: rec start [name] | rec fresh [name] | rec stop | rec"

static var _pending_fresh := ""

var console:   ConsoleCommands
var recorder:  ScenarioRecorder   # null when not recording
var frames:    int = 0


func setup(p_console: ConsoleCommands, instruments: InstrumentCommands) -> void:
    console = p_console
    console.player.action_validated.connect(_on_action)
    instruments.validated.connect(_on_action)
    console.thawing.connect(_on_thaw)
    console.draining_support.connect(_on_drain)

    for c in _table():
        if not LimboConsole.has_command(c[1]):
            LimboConsole.register_command(c[0], c[1], c[2])

    if not _pending_fresh.is_empty():
        VoxelEventBusSingleton.subscribe(WorldReadyEvent.CHANNEL, _on_world_ready)


func _table() -> Array:
    return [
        [rec,  "rec",  "Record play as a scenario in user://scenarios/<name>/ (doc 22). `rec start` records from this world once it has settled; `rec fresh` resets to the generator's world and records from its first frame; `rec stop` finishes. Usage: rec start [name] | rec fresh [name] | rec stop | rec"],
        [mark, "mark", "While recording: note this moment, and save the camera, FOV, dcworld settings, the aimed cell's probe report and a screenshot beside the steps. Usage: mark [note]"],
    ]


func _physics_process(_delta: float) -> void:
    frames += 1


func _exit_tree() -> void:
    if recorder != null:
        _finish()
    VoxelEventBusSingleton.unsubscribe(WorldReadyEvent.CHANNEL, _on_world_ready)
    if not is_instance_valid(LimboConsole):
        return
    for c in _table():
        if LimboConsole.has_command(c[1]):
            LimboConsole.unregister_command(c[1])


# --- rec ---

func rec(args: String = "") -> void:
    var words := args.split(" ", false)
    var verbs := {"start": _rec_start, "fresh": _rec_fresh, "stop": _rec_stop}
    if words.is_empty():
        _rec_status()
    elif verbs.has(words[0]) and words.size() <= 2:
        verbs[words[0]].call(words[1] if words.size() == 2 else _default_name())
    else:
        LimboConsole.error(USAGE)


func _rec_start(name: String) -> void:
    var dir := _new_dir(name)
    if dir.is_empty():
        return

    var r := ScenarioRecorder.new()
    if not r.start_save(dir, frames, console.host, console.edit_store):
        LimboConsole.error("rec start: %s" % r.error)
        return

    recorder = r
    LimboConsole.info("rec: recording into %s, from this world" % ProjectSettings.globalize_path(dir))


func _rec_fresh(name: String) -> void:
    var dir := _new_dir(name)
    if dir.is_empty():
        return

    _pending_fresh = dir
    LimboConsole.info("rec fresh: resetting to the generator's world; recording starts on its first frame")
    console.reset()


func _rec_stop(_name: String) -> void:
    if recorder == null:
        LimboConsole.error("rec stop: not recording")
        return
    _finish()


func _rec_status() -> void:
    if recorder == null:
        LimboConsole.info("rec: not recording. %s" % USAGE)
        return
    LimboConsole.info("rec: recording into %s, %d steps so far" % [
        ProjectSettings.globalize_path(recorder.dir), recorder.steps.size()])


func _finish() -> void:
    var r := recorder
    recorder = null
    if not r.stop(frames):
        LimboConsole.error("rec stop: %s; %s keeps the steps before it" % [r.error, r.dir])
        return
    LimboConsole.info("rec: stopped, %d steps in %s" % [r.steps.size(), ProjectSettings.globalize_path(r.dir)])


# A directory no recording has used yet, or "" (having said why).
func _new_dir(name: String) -> String:
    if recorder != null:
        LimboConsole.error("rec: already recording into %s" % recorder.dir)
        return ""
    var dir := ScenarioRecorder.dir_for(name)
    if dir.is_empty():
        LimboConsole.error("rec: \"%s\" isn't a plain file name" % name)
    elif DirAccess.dir_exists_absolute(dir):
        LimboConsole.error("rec: %s already exists; recordings aren't overwritten" % dir)
        dir = ""
    return dir


func _default_name() -> String:
    return Time.get_datetime_string_from_system().replace(":", "-")


func _on_world_ready(_event: VoxelEvent) -> void:
    VoxelEventBusSingleton.unsubscribe(WorldReadyEvent.CHANNEL, _on_world_ready)
    var dir := _pending_fresh
    _pending_fresh = ""

    var r := ScenarioRecorder.new()
    if not r.start_fresh(dir, frames):
        LimboConsole.error("rec fresh: %s" % r.error)
        return

    recorder = r
    LimboConsole.info("rec: recording into %s, from the generator's world" % ProjectSettings.globalize_path(dir))


# --- What's recorded ---

func _on_action(action: Action, valid: bool) -> void:
    if recorder != null:
        _check(recorder.action(action, valid, console.player.global_position, frames))

func _on_thaw(center: Vector3, radius: float) -> void:
    if recorder != null:
        _check(recorder.thaw(center, radius, frames))

func _on_drain() -> void:
    if recorder != null:
        _check(recorder.drain_support(frames))


# A step that couldn't be written ends the recording; what's on disk replays up to it.
func _check(ok: bool) -> void:
    if ok:
        return
    LimboConsole.error("rec: stopped, %s; %s keeps the steps before it" % [recorder.error, recorder.dir])
    recorder = null


# --- mark ---

# The step lands on this frame; the screenshot is taken once the console has slid out of the way
# (and the tree unpaused), a few frames later, so it's written after.
func mark(note: String = "") -> void:
    if recorder == null:
        LimboConsole.error("mark: not recording (rec start / rec fresh first)")
        return

    var r       := recorder
    var capture := _capture()
    var base    := r.mark(note, frames)
    if base.is_empty():
        _check(false)
        return

    var shot: Image = await _screenshot()
    if not r.save_capture(base, capture, shot):
        LimboConsole.error("mark: %s" % r.error)
        if r == recorder:
            recorder = null
        return
    LimboConsole.info("mark: %s in %s%s" % [base, ProjectSettings.globalize_path(r.dir),
        "" if shot != null else " (no screenshot: no rendered viewport)"])


func _capture() -> Dictionary:
    var player: CharacterBody3D = console.player
    var camera: Camera3D        = player.camera
    return {
        "player":  StepFields.encode_vec3(player.global_position),
        "camera":  {"transform": StepFields.encode_xform(camera.global_transform), "fov": camera.fov},
        "dcworld": _dcworld_settings(),
        "aim":     _aim(),
    }


# What `dcworld`, `dcrefine`, `dcretain`, `dcmaxcells`, `dcframebudget` and `dcthreads` read, plus
# the controller's operating point and the cell limit: what decides how the terrain was drawn at the mark.
func _dcworld_settings() -> Dictionary:
    var wp    := console.world_preview
    var cells := wp.cell_stats()

    return {
        "enabled":           wp.is_enabled(),
        "radius_m":          wp.win_radius_m,
        "base_cell_m":       wp.base_cell,
        "eps_px":            wp._eps_px,
        "frame_budget_ms":   wp.frame_budget,
        "refine_us":         wp.refine_us,
        "refine_pending":    wp._refine_pending,
        "retain_m":          wp.retain_margin_m,
        "max_cells":         wp.max_cells,
        "cell_capacity":     cells.capacity,
        "cell_limit":        cells.limit,
        "cells":             cells.slots,
        "live_cells":        cells.live,
        "cell_limit_hit":    cells.limit_hit,
        "at_cell_limit":     cells.at_limit,
        "mesher_busy":       wp.is_job_running(),
        "threads":           wp._mesher.get_thread_count(),
        "incremental_edits": wp.incremental_edits,
    }


# The surface under the crosshair and the probe's report of the cell behind it; null when the aim
# finds no surface within reach.
func _aim() -> Variant:
    var aim: Aim = console.player.current_target()
    if aim == null or not aim.hit:
        return null

    var integrity := console.integrity
    var ctx       := ActionContext.new(integrity.store, console.player, integrity, EditSource.Kind.INSTRUMENT)
    var probe     := ProbeAction.new(aim.position, aim.normal, Vector3.ZERO, ctx)
    return {
        "position": StepFields.encode_vec3(aim.position),
        "normal":   StepFields.encode_vec3(aim.normal),
        "cell":     StepFields.encode_cell(probe.target_cell()),
        "probe":    Array(probe.report()),
    }


# The frame as drawn, without the console over it; null headless, where nothing is drawn.
func _screenshot() -> Image:
    if DisplayServer.get_name() == "headless":
        return null
    if LimboConsole.is_open():
        LimboConsole.close_console()
        await LimboConsole.toggled
    await RenderingServer.frame_post_draw
    return get_viewport().get_texture().get_image()
