class_name ScenarioRecorder
extends RefCounted

# Doc 22's recorder (the record -> test loop, steps 1-3): turns what happened in a world into a
# scenario directory the replay runner (test/support/scenario.gd, run_recording) plays back.
#
# A directory holds steps.json (a StepDocument), and, when the recording started from a world
# rather than the generator, that world's save pair (world.snapshot + world.editstore). Each mark
# may add mark-NNN.json (what the view was) and mark-NNN.png.
#
# Time is the caller's: every call passes the simulation frame it happened on, counted as the
# frames the structural simulations actually ticked (a paused tree ticks nothing, so the engine's
# physics frame count is the wrong clock). A step is preceded by `advance` for the frames since the
# last one, and an action by `player_at` whenever the player has moved, because the safety checks
# read the player's position. steps.json is rewritten after every step, so a crash keeps
# everything up to the step before it.
# docs/roadmap/design/22-scenario-languages.md.
# (Drafted by Claude, overnight 2026-09-27.)

const ROOT           := "user://scenarios"
const STEPS_FILE     := "steps.json"
const SNAPSHOT_FILE  := "world.snapshot"
const EDITSTORE_FILE := "world.editstore"
const MARK_FORMAT    := "voxel-mvp/mark"
const MARK_VERSION   := 1

const _INDENT          := "  "
const _MARK_WRAP_DEPTH := 2   # a capture's sections wrap; the vectors and lists inside them don't

var dir:   String = ""
var steps: Array[Dictionary] = []
var error: String = ""   # why recording stopped short; "" while it's fine

var _frame:     int     = -1           # the frame of the last step; -1 before the start
var _player_at: Vector3 = Vector3.INF  # where the last player_at put the player
var _marks:     int     = 0
var _stopped:   bool    = false


# The directory `rec start <name>` records into; "" for a name that isn't a plain file name.
static func dir_for(name: String) -> String:
    if name.is_empty() or name != name.validate_filename():
        return ""
    return "%s/%s" % [ROOT, name]


func is_recording() -> bool:
    return _frame >= 0 and not _stopped and error == ""


# --- Starting ---

# From the generator alone: the directory gets no save pair, so a replay starts fresh.
func start_fresh(p_dir: String, frame: int) -> bool:
    if not _claim(p_dir):
        return false

    _frame = frame
    return _flush()


# From `world` as it stands, saved into the directory as a pair. Refused unless nothing structural
# is in flight: a save doesn't hold in-flight work, so the replay would start from a different world.
func start_save(p_dir: String, frame: int, world: Node, edit_store: EditStoreManager) -> bool:
    var integrity: StructuralIntegrity = world.get_node("StructuralIntegrity")
    if not integrity.is_quiescent():
        return _fail("the world is still settling; a recording starts from a world at rest")
    if not _claim(p_dir):
        return false

    var saved   := SavedWorld.new(_path(SNAPSHOT_FILE), _path(EDITSTORE_FILE))
    var problem := saved.save(world, edit_store)
    if not problem.is_empty():
        _unclaim()
        return _fail("the starting world didn't save: %s" % problem)

    _frame = frame
    return _flush()


# A new directory only: an old recording is never written over.
func _claim(p_dir: String) -> bool:
    if _frame >= 0:
        return _fail("already started")
    if DirAccess.dir_exists_absolute(p_dir):
        return _fail("%s already exists" % p_dir)

    var err := DirAccess.make_dir_recursive_absolute(p_dir)
    if err != OK:
        return _fail("can't make %s: %s" % [p_dir, error_string(err)])

    dir = p_dir
    return true

# Gives back a directory _claim just made, so a retry under the same name isn't refused; it holds
# only this attempt's files.
func _unclaim() -> void:
    for file in DirAccess.get_files_at(dir):
        DirAccess.remove_absolute(_path(file))
    DirAccess.remove_absolute(dir)
    dir = ""


# --- Recording ---

# An action that reached validate(), whatever it said; call before execute(), so the step holds the
# arguments the action ran with.
func action(act: Action, valid: bool, player_position: Vector3, frame: int) -> bool:
    var step := StepRegistry.step_of(act)
    if step.is_empty():
        return _fail("%s has no step op" % act.get_script().get_global_name())

    step["expect_valid"] = valid
    if player_position != _player_at:
        if not _add(StepRegistry.player_at(player_position), frame):
            return false
        _player_at = player_position
    return _add(step, frame)

# The console's `mpmthaw`.
func thaw(center: Vector3, radius: float, frame: int) -> bool:
    return _add(StepRegistry.thaw(center, radius), frame)

# The console's `settle`, which drains support at once rather than over frames.
func drain_support(frame: int) -> bool:
    return _add(StepRegistry.drain_support(), frame)

# A mark step naming its capture file; "" when it couldn't be recorded. What was on screen is
# written afterwards by save_capture(), because a screenshot arrives frames later.
func mark(note: String, frame: int) -> String:
    _marks += 1
    var base := "mark-%03d" % _marks
    return base if _add(StepRegistry.mark(note, base + ".json"), frame) else ""


# The frames since the last step, then the end. The directory stays as it was on a failure.
func stop(frame: int) -> bool:
    if not _advance_to(frame):
        return false

    _stopped = true
    return _flush()


# --- Mark captures ---

# `capture` is plain data (StepFields encodings); `shot` may be null (headless, or no viewport).
func save_capture(base: String, capture: Dictionary, shot: Image) -> bool:
    var doc := capture.duplicate()
    doc["format"]     = MARK_FORMAT
    doc["version"]    = MARK_VERSION
    doc["screenshot"] = null

    if shot != null and not shot.is_empty():
        var err := shot.save_png(_path(base + ".png"))
        if err != OK:
            return _fail("%s.png: %s" % [base, error_string(err)])
        doc["screenshot"] = base + ".png"

    var sj   := StepJson.new()
    var text := sj.stringify(doc, _INDENT, _MARK_WRAP_DEPTH)
    if sj.error != "":
        return _fail("%s.json: %s" % [base, sj.error])
    return _write(base + ".json", text + "\n")


# --- Internals ---

func _add(step: Dictionary, frame: int) -> bool:
    if not is_recording():
        return _fail(error if error != "" else "not recording")
    if not _advance_to(frame):
        return false

    steps.append(step)
    return _flush()


func _advance_to(frame: int) -> bool:
    if not is_recording():
        return _fail(error if error != "" else "not recording")
    if frame < _frame:
        return _fail("frame %d is before the last step's, %d" % [frame, _frame])

    if frame > _frame:
        steps.append(StepRegistry.advance(frame - _frame))
        _frame = frame
    return true


func _flush() -> bool:
    var doc := StepDocument.new()
    doc.steps = steps
    var text := doc.write()
    if doc.error != "":
        return _fail("steps: %s" % doc.error)
    return _write(STEPS_FILE, text)


# Under a temporary name, then renamed over the old file, so a crash mid-write keeps the last whole one.
func _write(file_name: String, text: String) -> bool:
    var tmp := _path(file_name + ".tmp")
    var f   := FileAccess.open(tmp, FileAccess.WRITE)
    if f == null:
        return _fail("%s: %s" % [file_name, error_string(FileAccess.get_open_error())])

    var wrote := f.store_string(text)
    f.close()
    if not wrote:
        return _fail("%s: the write failed" % file_name)

    var err := DirAccess.rename_absolute(tmp, _path(file_name))
    return err == OK or _fail("%s: %s" % [file_name, error_string(err)])


func _path(file_name: String) -> String:
    return "%s/%s" % [dir, file_name]


func _fail(problem: String) -> bool:
    if error == "":
        error = problem
    return false
