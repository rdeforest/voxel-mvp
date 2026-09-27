extends SceneTree

# Headless check of the live recorder wiring (doc 22 G4.3): the real World scene, driven through the
# console and the player's click, records `rec fresh` and `rec start` scenarios; each directory is
# then replayed by the runner and compared with the live world as it was at `rec stop`.
# Run: godot --path . --headless -s scripts/dev/probe_recorder_live.gd
# (Drafted by Claude, overnight 2026-09-27.)

# Everything game-side is loaded at run time and left untyped: a -s script compiles before the
# autoloads exist, and the game's scripts name them.
const SCENARIO := "res://test/support/scenario.gd"

var _captures := {}


func _initialize() -> void:
    for name in ["live-fresh", "live-start"]:
        _remove_tree("user://scenarios/" + name)
    change_scene_to_file("res://scenes/world/world.tscn")
    _run.call_deferred()


func _run() -> void:
    await _frames(10)
    _cmd("rec fresh live-fresh")
    await _frames(10)
    await _play("live-fresh", 0)

    await _frames(60)
    _cmd("settle")
    var integ = current_scene.get_node("StructuralIntegrity")
    var waited := 0
    while not integ.is_quiescent() and waited < 3000:
        await _frames(1)
        waited += 1
    print("PROBE waited %d frames to settle" % waited)
    print("PROBE quiescent=%s dirty=%d mpm_idle=%s scout_idle=%s" % [integ.is_quiescent(),
        integ.terrain_support.dirty_queue.size(), integ.mpm.is_idle(), integ.scout.is_idle()])
    _cmd("rec start live-start")
    await _play("live-start", 1)

    await _paused_clock()
    current_scene.free()
    await _frames(2)
    for name in _captures:
        _compare(name)
    quit()


func _play(name: String, variant: int) -> void:
    var world = current_scene
    var player = world.get_node("Player")
    player.head.rotation.x = -1.2
    player.rotation.y      = 0.7 * variant
    player.tool_index      = 1
    player._activity_indices[1] = 0   # Dig
    _cmd("tp %f -43 100.5" % (106.5 + 6.0 * variant))
    await _frames(40)
    var aim = player.current_target()
    print("PROBE %s: player %s aim %s raycast %s" % [name, player.global_position,
        aim.position if aim != null else null, player.raycast.is_colliding()])
    player._try_edit_terrain()
    await _frames(7)
    player._activity_indices[1] = 1   # Fill, at the player's feet: refused
    player.head.rotation.x = -1.5
    player._try_edit_terrain()
    _cmd("mark looking down")
    _cmd("mpmthaw 2")
    await _frames(13)
    player._activity_indices[1] = 0
    player.head.rotation.x = -1.0
    player._try_edit_terrain()
    await _frames(11)
    _cmd("rec stop")
    _captures[name] = _capture(world)
    print("PROBE %s: live frames=%d mpm=%d" % [name, world.get_node("RecordingCommands").frames,
        world._mpm_structure.active_count()])


# The open console pauses the tree: the recording's clock must stop with the simulations.
func _paused_clock() -> void:
    var clock = current_scene.get_node("RecordingCommands")
    var before: int = clock.frames
    var engine_before := Engine.get_physics_frames()
    paused = true
    await _frames(10)
    paused = false
    print("PROBE paused 10 frames: recording clock +%d, engine physics frames +%d" % [
        clock.frames - before, Engine.get_physics_frames() - engine_before])


func _capture(world: Node) -> Dictionary:
    var integrity = world.get_node("StructuralIntegrity")
    var voxels: Array = []
    var data = integrity.terrain_support.voxel_data
    for pos in data:
        voxels.append([pos, data[pos].material.name, data[pos].support, data[pos].dirty])
    return {
        "store":  world._edit_store.store.serialize(),
        "parts":  var_to_bytes(world.part_index().encode()),
        "voxels": var_to_bytes(voxels),
        "mpm":    var_to_bytes(world._mpm_structure.particle_positions()),
    }


func _compare(name: String) -> void:
    var s = load(SCENARIO).new()
    root.add_child(s)
    var ok = s.run_recording("user://scenarios/" + name)
    var got = s.capture()
    got.erase("player")
    var live: Dictionary = _captures[name]
    var doc = load("res://scripts/scenario/step_document.gd").new()
    doc.read(FileAccess.get_file_as_string("user://scenarios/%s/steps.json" % name))
    print("PROBE %s: replay ok=%s error=\"%s\" frames=%d steps=%s" % [name, ok, s.error, s.frame,
        doc.steps.map(func(st): return st["op"])])
    for key in live:
        print("PROBE %s: %s %s" % [name, key, "same" if live[key] == got[key] else "DIFFERENT"])
    print("PROBE %s: files %s" % [name, DirAccess.get_files_at("user://scenarios/" + name)])
    s.free()


func _frames(n: int) -> void:
    for _i in n:
        await physics_frame


func _remove_tree(path: String) -> void:
    if not DirAccess.dir_exists_absolute(path):
        return
    for file in DirAccess.get_files_at(path):
        DirAccess.remove_absolute("%s/%s" % [path, file])
    DirAccess.remove_absolute(path)


# The console autoload by path: a -s script compiles before autoload names exist.
func _cmd(line: String) -> void:
    root.get_node("LimboConsole").execute_command(line)
