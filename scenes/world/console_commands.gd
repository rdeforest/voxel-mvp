class_name ConsoleCommands
extends RefCounted

# Every Limbo console command, lifted out of world.gd so the World node stays about
# world lifecycle (streaming gate, save/load, subsystem wiring) and this object is
# about commands. The World builds one of these at _ready, assigns its collaborators,
# and calls register_all(); _exit_tree calls unregister_all().
#
# Everything here is a command, so there's no _cmd_ prefix. Two methods can't take the
# command's bare name because it collides with an Object built-in (`set`, `get`) — they
# are set_uniform / get_uniform; the command STRING the player types is still set/get.
# `host` is the World node, needed for get_tree() (reset/quit) and parenting the spawned
# PBD demo (this is RefCounted, so it can't add_child itself). The other collaborators
# are the subsystems World owns; assign them before register_all().

var host:              Node
var dc_manager:        DCTerrainManager
var substrate_preview: DcSubstratePreview
var pbd_structure:     PbdStructure
var integrity:         StructuralIntegrity
var player:            CharacterBody3D
var awake_overlay:     AwakeOverlay
var edit_store:        EditStoreManager
var part_index:        PartIndex

var _pbd_demo: PbdDemo   # lazily spawned by `pbddemo`
var _mpm_demo: MpmDemo   # lazily spawned by `mpmdemo`


# The LimboConsole autoload outlives the World scene. On reload (F9 / reset) the old
# world is freed; a command left registered would point at a freed object and crash
# LimboConsole's introspection. So World registers on _ready and unregisters on
# _exit_tree, keeping bindings live. One table feeds both so the names can't drift.
func register_all() -> void:
    for c in _table():
        if not LimboConsole.has_command(c[1]):
            LimboConsole.register_command(c[0], c[1], c[2])

func unregister_all() -> void:
    if not is_instance_valid(LimboConsole):
        return
    for c in _table():
        if LimboConsole.has_command(c[1]):
            LimboConsole.unregister_command(c[1])

func _table() -> Array:
    return [
        [set_uniform,     "set",       "Set a terrain shader uniform (float). Usage: set <name> <value>"],
        [get_uniform,     "get",       "List terrain shader uniforms matching a glob (default *). Usage: get [pattern]"],
        [dcmanager,       "dcmanager", "Toggle the DC terrain manager (threaded re-mesh of a bubble around you). Usage: dcmanager [on|off]"],
        [dcerror,         "dcerror",   "Toggle error-driven terrain LOD (screen-space error vs distance bands). Usage: dcerror [on|off]"],
        [dceps,           "dceps",     "Set the error-driven LOD threshold in px (lower = more detail). Usage: dceps <px>"],
        [dcdump,          "dcdump",    "Write the next clipmap dispatch's mesher inputs to user://dcdump.dat (diagnostic)."],
        [dcaudit,         "dcaudit",   "Re-mesh and report suspect terrain triangles (degenerate/sliver/tilted) in world coords. Usage: dcaudit"],
        [dcgen,           "dcgen",     "Phase B preview: render the octree-over-generator substrate (cyan) at your position. Usage: dcgen [on|off]"],
        [editstore,       "editstore", "Print the EditStore's edited-leaf count + its SDF at your position."],
        [pbddemo,         "pbddemo",   "PBD demo: spawn a live mass-spring structure (stress-coloured) to watch sag/fail. Usage: pbddemo [cantilever|bridge|tower] [size]"],
        [mpmdemo,         "mpmdemo",   "PB-MPM demo: spawn a live block of continuum material that falls and rests ON the terrain. Usage: mpmdemo [size]"],
        [physics_active,  "physics_active", "Toggle the structural physics simulation on your real structures (sag + collapse under load). Usage: physics_active [on|off]"],
        [perf,            "perf",      "Toggle the performance overlay (FPS + per-subsystem ms, bottom-right). Usage: perf [on|off]"],
        [awake,           "awake",     "Highlight awake physics bodies (debris / collapsed parts) with a box. Usage: awake [on|off]"],
        [reset,           "reset",     "Delete the save (EditStore blob + snapshot) and reload to a fresh world."],
        [quiescent,       "quiescent", "Print whether the world is quiescent (save-ready)."],
        [settle,          "settle",    "Force the world to rest so a save is never blocked (drains support, sleeps PBD + falling bodies)."],
        [parts,           "parts",     "Print the number of tracked parts."],
        [voxels,          "voxels",    "Print the number of tracked terrain voxels."],
        [tp,              "tp",        "Teleport the player. Usage: tp <x> <y> <z>"],
        [quit_game,       "quit_game", "Exit the game (separate from console's built-in quit)."],
    ]


# A console toggle's new state: empty arg flips `current`, otherwise "on" sets true.
func _parse_toggle(state: String, current: bool) -> bool:
    return not current if state == "" else state == "on"


func set_uniform(param: String, value: float) -> void:
    var mat := dc_manager.terrain_material
    if mat == null:
        LimboConsole.error("no terrain material")
        return
    mat.set_shader_parameter(param, value)   # one MeshInstance now — the change is live
    LimboConsole.info("%s = %s" % [param, value])

func get_uniform(pattern: String = "*") -> void:
    var mat := dc_manager.terrain_material
    if mat == null:
        LimboConsole.error("no terrain material")
        return
    var found := 0
    for prop in mat.get_property_list():
        var pname: String = prop.name
        if not pname.begins_with("shader_parameter/"):
            continue
        var uniform := pname.substr("shader_parameter/".length())
        if not uniform.matchn(pattern):
            continue
        # get_shader_parameter returns the override, or null when the uniform is at its
        # shader default (not yet set on this material).
        var v: Variant = mat.get_shader_parameter(uniform)
        LimboConsole.info("%s = %s" % [uniform, "(default)" if v == null else v])
        found += 1
    if found == 0:
        LimboConsole.info("no shader uniforms match '%s'" % pattern)

func dcmanager(state := "") -> void:
    var on := _parse_toggle(state, dc_manager.is_enabled())
    dc_manager.set_enabled(on)
    LimboConsole.info("dcmanager: %s" % ("on" if on else "off"))

func dcerror(state := "") -> void:
    var on := _parse_toggle(state, dc_manager.error_driven)
    dc_manager.error_driven = on
    dc_manager.remesh()
    LimboConsole.info("dcerror: %s (eps %.2f px)" % [("on" if on else "off"), dc_manager.eps_px])

func dceps(px: float) -> void:
    dc_manager.eps_px = maxf(0.01, px)
    dc_manager.remesh()
    LimboConsole.info("dceps: %.2f px" % dc_manager.eps_px)

func dcdump() -> void:
    dc_manager.dump_next = true
    dc_manager.remesh()
    LimboConsole.info("dcdump: writing user://dcdump.dat on next re-mesh")

func dcaudit() -> void:
    dc_manager.audit_current_mesh()
    LimboConsole.info("dcaudit: scanned the on-screen mesh; suspect triangles printed to stdout (Debug Console)")

# `dcgen on` starts the live substrate render (follows you, threaded re-mesh); `dcgen off` hides it.
func dcgen(state := "") -> void:
    var on := _parse_toggle(state, substrate_preview.is_enabled())
    substrate_preview.set_enabled(on)
    LimboConsole.info("dcgen: %s (live octree-over-generator render, cyan)" % ("on" if on else "off"))

# Spawn a live PBD structural-physics demo in front of the player (stress-coloured
# lines; watch it sag and snap). Re-run to reset.
# How many edited leaves the store holds + its SDF at your position.
func editstore() -> void:
    var here := player.global_position
    LimboConsole.info("editstore: %d edited leaves; at you store=%.2f" % [
        edit_store.store.leaf_count(), edit_store.store.sample(here)])


func pbddemo(kind := "cantilever", size := 12) -> void:
    var fwd := -player.global_transform.basis.z
    var base := Vector3i((player.global_position + fwd * 6.0 + Vector3.UP * 4.0).round())
    var sim: PbdSim
    match kind:
        "bridge": sim = PbdDemo.bridge(base, size)
        "tower":  sim = PbdDemo.tower(base, size)
        _:        sim = PbdDemo.cantilever(base, size)
    if _pbd_demo == null:
        _pbd_demo = PbdDemo.new()
        host.add_child(_pbd_demo)
    _pbd_demo.set_sim(sim)
    LimboConsole.info("pbddemo: %s size %d (%d members)" % [kind, size, sim.member_count()])

# Spawn a live PB-MPM block of elastic material in front of the player; it falls and rests on the
# real terrain (the EditStore SDF is its collider). Re-run to respawn.
func mpmdemo(size := 4) -> void:
    var fwd := -player.global_transform.basis.z
    var center := player.global_position + fwd * 5.0 + Vector3.UP * 4.0
    if _mpm_demo == null:
        _mpm_demo = MpmDemo.new()
        host.add_child(_mpm_demo)
    _mpm_demo.setup(center, size, edit_store.store)
    LimboConsole.info("mpmdemo: %d cubed elastic block at %s (PB-MPM, rests on terrain)" % [size, center])

func physics_active(state := "") -> void:
    var on := _parse_toggle(state, pbd_structure.is_enabled())
    pbd_structure.set_enabled(on)
    LimboConsole.info("physics_active: %s" % ("on" if on else "off"))

func perf(state := "") -> void:
    var on := _parse_toggle(state, Perf.is_shown())
    Perf.set_shown(on)
    LimboConsole.info("perf: %s" % ("on" if on else "off"))

func awake(state := "") -> void:
    var on := _parse_toggle(state, awake_overlay.is_enabled())
    awake_overlay.set_enabled(on)
    LimboConsole.info("awake highlight: %s" % ("on" if on else "off"))


func reset() -> void:
    # Save files are left untouched on disk. Next scene-reload runs with
    # `reset_pending = true`, which detaches the terrain stream (procedural terrain
    # regenerates) and skips the snapshot load. F9 afterwards reloads normally.
    WorldSnapshot.reset_pending = true
    LimboConsole.info("Resetting to defaults — saves left intact. F9 to restore.")
    host.get_tree().reload_current_scene.call_deferred()

func quiescent() -> void:
    LimboConsole.info("quiescent: %s" % integrity.is_quiescent())

func settle() -> void:
    integrity.force_quiescent()
    LimboConsole.info("settled — quiescent: %s" % integrity.is_quiescent())

func parts() -> void:
    LimboConsole.info("parts: %d (PartIndex)" % part_index.count())

func voxels() -> void:
    LimboConsole.info("tracked voxels: %d" % integrity.terrain_support.voxel_data.size())

func tp(x: float, y: float, z: float) -> void:
    player.global_position = Vector3(x, y, z)
    LimboConsole.info("teleported to %s" % player.global_position)

func quit_game() -> void:
    host.get_tree().quit()
