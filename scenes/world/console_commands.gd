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
var inval_overlay:     Node3D
var substrate_preview: DcSubstratePreview
var world_preview:     DcWorldPreview
var pbd_structure:     PbdStructure
var integrity:         StructuralIntegrity
var player:            CharacterBody3D
var awake_overlay:     AwakeOverlay
var edit_store:        EditStoreManager
var part_index:        PartIndex

var _pbd_demo: PbdDemo   # lazily spawned by `pbddemo`
var _mpm_demo: MpmDemo   # lazily spawned by `mpmdemo`
var _flood_viz: FloodViz   # lazily spawned by `floodviz`


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
        [savestyle,       "savestyle", "Save the current watercolour/terrain shader settings as a named preset. Usage: savestyle <name>"],
        [loadstyle,       "loadstyle", "Load a saved shader-settings preset. Usage: loadstyle <name>"],
        [liststyles,      "liststyles","List saved shader-settings presets."],
        [dcmanager,       "dcmanager", "Toggle the DC terrain manager (threaded re-mesh of a bubble around you). Usage: dcmanager [on|off]"],
        [dcerror,         "dcerror",   "Toggle screen-error terrain LOD (collapse by projected QEF residual in px). Usage: dcerror [on|off]"],
        [dcinval,         "dcinval",   "Toggle the invalidation overlay: blue=voxels an edit changed, green=region re-meshed, fading. Shows what each edit/move redoes."],
        [dcbudget,        "dcbudget",  "Toggle the B2 detail budget: auto-tune the LOD threshold toward a frame-time target (refine on slack, coarsen over budget). Usage: dcbudget [on|off]"],
        [dceps,           "dceps",     "Set the screen-error LOD threshold (px; lower = more detail). Usage: dceps <px>"],
        [fov,             "fov",       "Set the camera field-of-view in degrees (low = telescope/zoom → distant terrain refines under screen-error LOD). Usage: fov <degrees>"],
        [dccore,          "dccore",    "Toggle the uniform 1m fine core: ON pins fine cells around you (clean edit splices); OFF lets the core collapse by screen-error too (uniform huge tris at high dceps, but edits may crack). Usage: dccore [on|off]"],
        [dcprune,         "dcprune",   "Toggle the surface-sparse build (exact min/max prune — skips provably-empty cells, fast rebuild). 1 = on (default), 0 = dense build (slow, for comparison). Usage: dcprune <0|1>"],
        [examine,         "examine",   "Examine mode: freeze DC re-meshing + noclip free-flight + magenta backfaces (tell a backwards triangle from a hole). Also Ctrl+E. Usage: examine [on|off]"],
        [dcdump,          "dcdump",    "Write the next clipmap dispatch's mesher inputs to user://dcdump.dat (diagnostic)."],
        [dcaudit,         "dcaudit",   "Re-mesh and report suspect terrain triangles (degenerate/sliver/tilted) in world coords. Usage: dcaudit"],
        [dcgen,           "dcgen",     "Phase B preview: render the octree-over-generator substrate (cyan) at your position. Usage: dcgen [on|off]"],
        [dcworld,         "dcworld",   "doc 16: render the WORLD-FIXED incremental octree (amber bubble; mesh_world + grow_world on move). Dense build → small bubble until the prune lands. Tip: dcmanager off to see it alone. Usage: dcworld [on|off]"],
        [editstore,       "editstore", "Print the EditStore's edited-leaf count + its SDF at your position."],
        [pbddemo,         "pbddemo",   "PBD demo: spawn a live mass-spring structure (stress-coloured) to watch sag/fail. Usage: pbddemo [cantilever|bridge|tower] [size]"],
        [mpmdemo,         "mpmdemo",   "PB-MPM demo: spawn a live block of continuum material that falls and rests ON the terrain. Usage: mpmdemo [size]"],
        [mpmthaw,         "mpmthaw",   "Thaw the REAL terrain at your aim into MPM: it carves out, falls/deforms, and freezes back when settled. Usage: mpmthaw [radius]"],
        [physics_mode,    "physics_mode", "Switch the structural sim: 'pbd' (mass-spring, default) or 'mpm' (PB-MPM continuum — unsupported terrain thaws/falls/freezes). Usage: physics_mode [pbd|mpm]"],
        [floodviz,        "floodviz",  "Debug: flood connected solid terrain from your aim (biased down), colouring reached surface cells green. Non-blocking. Usage: floodviz [cells_per_frame]"],
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


# --- Shader-settings presets (the watercolour tuning + any terrain-shader overrides) ---

const STYLES_DIR := "user://styles"
const POST_MAT_PATH := "res://assets/materials/watercolor_post.tres"

# The materials a style spans, keyed for the file: the terrain wash + the ink/vignette post-process.
func _style_materials() -> Dictionary:
    return {"terrain": dc_manager.terrain_material, "post": load(POST_MAT_PATH)}

func _style_path(name: String) -> String:
    return "%s/%s.txt" % [STYLES_DIR, name.validate_filename()]

func savestyle(name := "") -> void:
    if name == "":
        LimboConsole.error("usage: savestyle <name>")
        return
    var data := {}
    for key in _style_materials():
        var mat: ShaderMaterial = _style_materials()[key]
        var params := {}
        if mat != null:
            for prop in mat.get_property_list():
                var pname: String = prop.name
                if not pname.begins_with("shader_parameter/"):
                    continue
                var uniform := pname.substr("shader_parameter/".length())
                var v: Variant = mat.get_shader_parameter(uniform)
                if v != null:                       # null = at shader default, nothing to save
                    params[uniform] = v
        data[key] = params
    DirAccess.make_dir_recursive_absolute(STYLES_DIR)
    var f := FileAccess.open(_style_path(name), FileAccess.WRITE)
    if f == null:
        LimboConsole.error("can't write %s" % _style_path(name))
        return
    f.store_string(var_to_str(data))
    f.close()
    LimboConsole.info("saved style '%s' (%d terrain + %d post params)" % [name, data["terrain"].size(), data["post"].size()])

func loadstyle(name := "") -> void:
    if name == "":
        LimboConsole.error("usage: loadstyle <name>")
        return
    var f := FileAccess.open(_style_path(name), FileAccess.READ)
    if f == null:
        LimboConsole.error("no style '%s' (try `liststyles`)" % name)
        return
    var data: Variant = str_to_var(f.get_as_text())
    f.close()
    if typeof(data) != TYPE_DICTIONARY:
        LimboConsole.error("style '%s' is corrupt" % name)
        return
    var applied := 0
    var mats := _style_materials()
    for key in mats:
        var mat: ShaderMaterial = mats[key]
        if mat == null or not data.has(key):
            continue
        for uniform in data[key]:
            mat.set_shader_parameter(uniform, data[key][uniform])
            applied += 1
    LimboConsole.info("loaded style '%s' (%d params)" % [name, applied])

func liststyles() -> void:
    var dir := DirAccess.open(STYLES_DIR)
    if dir == null:
        LimboConsole.info("no styles saved yet")
        return
    var found := 0
    for fn in dir.get_files():
        if fn.ends_with(".txt"):
            LimboConsole.info("  " + fn.trim_suffix(".txt"))
            found += 1
    if found == 0:
        LimboConsole.info("no styles saved yet")


func dcmanager(state := "") -> void:
    var on := _parse_toggle(state, dc_manager.is_enabled())
    dc_manager.set_enabled(on)
    LimboConsole.info("dcmanager: %s" % ("on" if on else "off"))

func dcinval(_state := "") -> void:
    var on: bool = inval_overlay.toggle()
    dc_manager.debug_invalidation = on   # gates the (costly) per-edit triangle scan
    LimboConsole.info("dcinval: %s — blue=voxels changed, green=triangles re-meshed (fades)" % ("on" if on else "off"))

func dcbudget(state := "") -> void:
    var on := _parse_toggle(state, dc_manager.budget_enabled)
    dc_manager.budget_enabled = on
    LimboConsole.info("dcbudget: %s (target %.0f ms/frame, eps now %.2fpx)" % [
        ("on" if on else "off"), DCTerrainManager.BUDGET_TARGET_MS, dc_manager.eps_px])

func dcerror(state := "") -> void:
    var on := _parse_toggle(state, dc_manager.error_driven)
    dc_manager.error_driven = on
    dc_manager.remesh()
    LimboConsole.info("dcerror: %s (eps %.2fpx)" % [("on" if on else "off"), dc_manager.eps_px])

func dceps(px: float) -> void:
    dc_manager.set_eps(maxf(0.1, px))   # cheap in-place re-collapse (retained octree), no field re-sample
    LimboConsole.info("dceps: %.2fpx" % dc_manager.eps_px)

func dcprune(factor: float) -> void:
    dc_manager.prune_safety = maxf(0.0, factor)
    dc_manager.remesh()
    LimboConsole.info("dcprune: %.2f (%s)" % [dc_manager.prune_safety,
        "dense build" if dc_manager.prune_safety == 0.0 else "surface-sparse"])

func fov(degrees: float) -> void:
    var cam := host.get_viewport().get_camera_3d()
    if cam == null:
        LimboConsole.error("fov: no active camera")
        return
    cam.fov = clampf(degrees, 1.0, 179.0)   # the DC manager polls FOV each frame → auto re-mesh
    LimboConsole.info("fov: %.1f°" % cam.fov)

func dccore(state := "") -> void:
    var on := _parse_toggle(state, dc_manager.uniform_core)
    dc_manager.uniform_core = on
    dc_manager.remesh()
    LimboConsole.info("dccore: %s (fine 1m core %s)" % [("on" if on else "off"), ("pinned" if on else "collapsible")])

# Freeze the render so a defect holds still, fly through it (noclip), and colour backfaces magenta
# so a backwards triangle (gap fills magenta) reads differently from a missing one (gap stays open).
func examine(state := "") -> void:
    var on := _parse_toggle(state, dc_manager.frozen)
    dc_manager.frozen = on
    dc_manager.set_debug_backface(on)
    player.set_examine_movement(on)
    LimboConsole.info("examine: %s — re-mesh %s, noclip fly %s, magenta backfaces %s" % [
        ("ON" if on else "off"), ("FROZEN" if on else "live"),
        ("on" if on else "off"), ("on" if on else "off")])

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

# `dcworld on [radius_m]` renders the doc-17 world-fixed octree (amber, overlaid, 0.25 m), graded by the
# screen-error budget controller: eps_px starts coarse and self-tunes against frame time + mesh lag
# (~100 ms target, 500 ms ceiling). Coverage is the window radius (default 128 m). `dcmanager off` to see it
# alone. `dcworld` (no args) prints the live eps_px + last mesh-lag.
func dcworld(state := "", radius := 0.0) -> void:
    if radius > 0.0:
        world_preview.set_radius(radius)
    if state == "" and radius == 0.0 and world_preview.is_enabled():
        LimboConsole.info("dcworld: on, %.0fm coverage, eps_px=%.1f, last mesh-lag=%.0fms" % [
            world_preview.win_radius_m, world_preview._eps_px, world_preview._job_work_ms])
        return
    var on := _parse_toggle(state, world_preview.is_enabled())
    world_preview.set_enabled(on)
    LimboConsole.info("dcworld: %s (world-fixed octree, %.0fm coverage @ %.2fm cells, budget-tuned eps)%s" % [
        "on" if on else "off", world_preview.win_radius_m, world_preview.base_cell,
        " — tip: `dcmanager off` to see it alone" if on else ""])

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

# Thaw the real terrain at the player's aim into MPM material: it carves out of the store, falls
# and deforms against the rest of the terrain, then freezes back in when it settles.
func mpmthaw(radius := 3.0) -> void:
    var rc: RayCast3D = player.raycast
    if rc == null or not rc.is_colliding():
        LimboConsole.error("mpmthaw: aim at terrain first")
        return
    # Thaw into the world's wired MpmStructure (the same one save-gating + physics_mode see), not a
    # private console instance — otherwise the in-flight material is invisible to is_quiescent.
    var n := integrity.mpm.thaw_sphere(rc.get_collision_point(), radius)
    LimboConsole.info("mpmthaw: thawed %d cells (r=%.1f) into MPM" % [n, radius])

# Debug-flood connected solid terrain from the cell behind the player's aim, biased downward,
# colouring reached surface cells green so you can watch how far/fast a "connected to ground"
# search spreads. Scouts the eventual MPM detachment trigger.
func floodviz(budget := 200) -> void:
    var rc: RayCast3D = player.raycast
    if rc == null or not rc.is_colliding():
        LimboConsole.error("floodviz: aim at terrain first")
        return
    var cell := Vector3i((rc.get_collision_point() - rc.get_collision_normal() * 0.5).floor())
    if _flood_viz == null:
        _flood_viz = FloodViz.new()
        host.add_child(_flood_viz)
        _flood_viz.setup(edit_store.store)
    _flood_viz.start(cell, budget)
    LimboConsole.info("floodviz: flooding from %s at %d cells/frame (green = reached surface)" % [cell, budget])


# Switch the authoritative structural sim. `mpm` disables PBD and routes loss-of-support cells
# into the PB-MPM substrate (thaw → fall → freeze); `pbd` restores the mass-spring sim.
func physics_mode(mode := "") -> void:
    if mode == "mpm":
        integrity.mpm_mode = true
        pbd_structure.set_enabled(false)
        LimboConsole.info("physics_mode: MPM (PB-MPM continuum) — PBD disabled")
    elif mode == "pbd":
        integrity.mpm_mode = false
        if integrity.mpm != null:
            integrity.mpm.reset()   # drop any in-flight MPM material so it stops being stepped
        pbd_structure.set_enabled(true)
        LimboConsole.info("physics_mode: PBD (mass-spring)")
    else:
        LimboConsole.info("physics_mode: %s" % ("mpm" if integrity.mpm_mode else "pbd"))

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
