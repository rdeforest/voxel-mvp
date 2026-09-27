extends GutTest

# RunPaths (test/support/run_paths.gd): every GUT process writes under a directory of its own, the
# game's save and recording roots follow it, and a run's start sweeps out only the directories
# of runs that are gone. Two runs at once used to overwrite each other's fixed-name files in the
# shared user://, and the named-save test wrote into the player's user://saves.
# (Drafted by Claude, overnight 2026-09-27.)

const RunPaths := preload("res://test/support/run_paths.gd")

var _fixture: String


func before_each() -> void:
    _fixture = RunPaths.path("test_run_paths")
    RunPaths.remove_tree(_fixture)
    DirAccess.make_dir_recursive_absolute(_fixture)

# test_release hands the game its real roots back mid-run; if it dies before claiming again, the
# claim here keeps every later script off the player's saves.
func after_each() -> void:
    RunPaths.remove_tree(_fixture)
    RunPaths.root()


func _touch(path: String) -> void:
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    FileAccess.open(path, FileAccess.WRITE).store_string("x")

# The pid of a process that has come and gone.
func _dead_pid() -> int:
    var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--version"])
    assert_gt(pid, 0, "the child starts")
    await wait_until(func() -> bool: return not OS.is_process_running(pid), 30, "the child exits")
    return pid


func test_the_root_is_this_process_own() -> void:
    assert_eq(RunPaths.root(), "%s/%d" % [RunPaths.RUNS, OS.get_process_id()])
    assert_true(DirAccess.dir_exists_absolute(RunPaths.root()), "and exists")

func test_the_game_saves_and_records_under_it_not_in_the_player_saves() -> void:
    var inside := RunPaths.root() + "/"
    for dir in [SaveSlot.dir_of(SaveSlot.DEFAULT), SaveSlot.dir_of("slot"), ScenarioRecorder.dir_for("take")]:
        assert_true(dir.begins_with(inside), "%s is under %s" % [dir, inside])
    assert_true(SaveSlot.snapshot_path(SaveSlot.DEFAULT).begins_with(inside), "F5's snapshot too")


func test_a_sweep_removes_dead_runs_and_keeps_live_ones() -> void:
    var dead := await _dead_pid()
    _touch("%s/%d/left.tmp" % [_fixture, dead])
    _touch("%s/%d/live.tmp" % [_fixture, OS.get_process_id()])
    _touch("%s/not_a_run/kept.tmp" % _fixture)

    RunPaths.sweep(_fixture)
    assert_false(DirAccess.dir_exists_absolute("%s/%d" % [_fixture, dead]), "a dead run's directory goes")
    assert_true(FileAccess.file_exists("%s/%d/live.tmp" % [_fixture, OS.get_process_id()]),
        "a live run's stays, though it isn't this process's child")
    assert_true(FileAccess.file_exists("%s/not_a_run/kept.tmp" % _fixture), "what isn't a run is left")

func test_is_running_knows_processes_it_did_not_start() -> void:
    assert_true(RunPaths.is_running(OS.get_process_id()), "this process")
    assert_false(RunPaths.is_running(await _dead_pid()), "a process that has exited")


func test_a_claim_empties_what_a_dead_run_with_this_pid_left() -> void:
    _touch("%s/%d/stale.tmp" % [_fixture, OS.get_process_id()])
    var own := RunPaths.claim(_fixture)
    assert_eq(own, "%s/%d" % [_fixture, OS.get_process_id()])
    assert_true(DirAccess.dir_exists_absolute(own), "the directory is there")
    assert_eq(Array(DirAccess.get_files_at(own)), [], "and empty")


func test_release_removes_the_directory_and_gives_the_game_its_roots_back() -> void:
    var root := RunPaths.root()
    _touch(RunPaths.path("released.tmp"))
    RunPaths.release()
    assert_false(DirAccess.dir_exists_absolute(root), "the directory is gone")
    assert_eq(SavePaths.root, SavePaths.DEFAULT_ROOT, "saves go to the player's again")
    assert_eq(ScenarioRecorder.root, ScenarioRecorder.DEFAULT_ROOT, "and recordings")

    assert_eq(RunPaths.root(), root, "the next use claims it again")
    assert_true(SaveSlot.dir_of(SaveSlot.DEFAULT).begins_with(root + "/"), "and points the game back into it")
