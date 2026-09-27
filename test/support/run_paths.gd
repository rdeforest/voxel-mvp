extends RefCounted

# Where tests put files: a directory of this process's own, user://test_runs/<pid>/. user:// is per
# project name, so every checkout's GUT runs share it; with fixed names, concurrent runs overwrote
# each other's files. The game's save and recording roots are pointed into it too, so no test
# reads or writes the player's saves.
#
# The pre-run hook claims it before the first test and the post-run hook releases it. A runner
# without the hooks (the editor's GUT panel) claims it on first use and leaves it for the next
# run's sweep, as does a run that dies.
# docs/BUILD.md, Tests.
# (Drafted by Claude, overnight 2026-09-27.)

const RUNS := "user://test_runs"

enum Answer { RUNNING, GONE, UNKNOWN }

static var _root := ""


static func root() -> String:
    if _root.is_empty():
        _root = claim(RUNS)
        SavePaths.root        = path("saves")
        ScenarioRecorder.root = path("scenarios")
    return _root

static func path(name: String) -> String:
    return "%s/%s" % [root(), name]


# Removes this process's directory and hands the game its real roots back.
static func release() -> void:
    if _root.is_empty():
        return

    remove_tree(_root)
    _root = ""
    SavePaths.root        = SavePaths.DEFAULT_ROOT
    ScenarioRecorder.root = ScenarioRecorder.DEFAULT_ROOT


# An empty directory for this process under `runs`, after sweeping out the runs that are gone. One
# already there is a dead run's that had this pid, so it's emptied.
static func claim(runs: String) -> String:
    sweep(runs)
    var own := "%s/%d" % [runs, OS.get_process_id()]
    remove_tree(own)

    var err := DirAccess.make_dir_recursive_absolute(own)
    if err != OK:
        push_error("RunPaths: can't make %s: %s" % [own, error_string(err)])
    return own


# Removes every run directory under `runs` whose process is gone. A pid reused since only delays
# the removal; a live run's directory is never touched.
static func sweep(runs: String) -> void:
    if not DirAccess.dir_exists_absolute(runs):
        return

    for name in DirAccess.get_directories_at(runs):
        if name.is_valid_int() and not is_running(name.to_int()):
            remove_tree("%s/%s" % [runs, name])


# OS.is_process_running only knows this process's children (it waitpid()s), so it calls any other
# process gone; ask the OS instead. A check that can't run, or answers in a way we don't know,
# counts as running: that leaks a directory rather than deleting a live run's.
static func is_running(pid: int) -> bool:
    var out    := []
    var answer := _tasklist(pid, out) if OS.has_feature("windows") else _ps(pid, out)
    if answer == Answer.UNKNOWN:
        push_warning("RunPaths: can't tell whether %d is running (%s); keeping its directory"
            % [pid, "".join(out).strip_edges()])
    return answer != Answer.GONE


# `ps -o pid= -p N` prints just the pid when it exists; nothing, with status 1, when it doesn't.
static func _ps(pid: int, out: Array) -> Answer:
    var status := OS.execute("ps", ["-o", "pid=", "-p", str(pid)], out)
    var said   := "".join(out).strip_edges()
    if status == 0 and said == str(pid):
        return Answer.RUNNING
    if status == 1 and said.is_empty():
        return Answer.GONE
    return Answer.UNKNOWN

# tasklist prints the process's CSV row, or an "INFO:" line when no process matches the filter.
static func _tasklist(pid: int, out: Array) -> Answer:
    var status := OS.execute("tasklist", ["/NH", "/FO", "CSV", "/FI", "PID eq %d" % pid], out)
    var said   := "".join(out)
    if status != 0:
        return Answer.UNKNOWN
    if ("\"%d\"" % pid) in said:
        return Answer.RUNNING
    if said.strip_edges().begins_with("INFO:"):
        return Answer.GONE
    return Answer.UNKNOWN


static func remove_tree(dir: String) -> void:
    if not DirAccess.dir_exists_absolute(dir):
        return

    for sub in DirAccess.get_directories_at(dir):
        remove_tree("%s/%s" % [dir, sub])
    for file in DirAccess.get_files_at(dir):
        DirAccess.remove_absolute("%s/%s" % [dir, file])
    DirAccess.remove_absolute(dir)
