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
# demos (this is RefCounted, so it can't add_child itself). The other collaborators
# are the subsystems World owns; assign them before register_all().

var host:          Node
var inval_overlay: Node3D
var world_preview: DcWorldPreview
var integrity:         StructuralIntegrity
var player:            CharacterBody3D
var awake_overlay:     AwakeOverlay
var edit_store:        EditStoreManager
var part_index:        PartIndex

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
        [dcinval,         "dcinval",   "Toggle the invalidation overlay: red=triangle too big on screen, yellow=too small; fading. Shows what each edit/move redoes."],
        [fov,             "fov",       "Set the camera field-of-view in degrees (low = telescope/zoom → distant terrain refines under screen-error LOD). Usage: fov <degrees>"],
        [examine,         "examine",   "Examine mode: freeze DC re-meshing + noclip free-flight (tell a backwards triangle from a hole). Also Ctrl+E. Usage: examine [on|off]"],
        [dcworld,         "dcworld",   "doc 17: the WORLD-FIXED octree render. `dcworld on|off` toggles; `dcworld <radius_m>` sets coverage + turns on (default 128); no args prints live eps_px + job ms."],
        [dcrefine,        "dcrefine",  "doc 20 C/P: wall-clock cap (ms) on refine work per grow while the world blooms in — do as much as fits in X ms, worst-on-screen first. Higher = faster bloom, longer per-job latency. Usage: dcrefine [ms] (default 8)"],
        [dcretain,        "dcretain",  "doc 20 M: metres kept resident BEYOND the visible window — a turn or backtrack within it re-samples nothing (no re-bloom), and the edge ahead is pre-baked. Higher = more retention + cost. Usage: dcretain [m] (default 128)"],
        [dcframebudget,   "dcframebudget", "Per-frame render budget (ms) the controller refines toward — refines while render cost < half this, backs off above it. Higher = more detail, lower fps. Usage: dcframebudget [ms] (default 16)"],
        [dcthreads,       "dcthreads", "Parallel accel-bake workers: `dcthreads <n>` sets the thread count; no args prints the phase timing (accel + build + collapse ms). Usage: dcthreads [n]"],
        [remesh,          "remesh",    "Force a full dcworld rebuild now (re-bake + build + collapse) — trigger a remesh without walking, then read `dcthreads` for the timing."],
        [editstore,       "editstore", "Print the EditStore's edited-leaf count + its SDF at your position."],
        [mpmdemo,         "mpmdemo",   "PB-MPM demo: spawn a live block of continuum material that falls and rests ON the terrain. Usage: mpmdemo [size]"],
        [mpmthaw,         "mpmthaw",   "Thaw the REAL terrain at your aim into MPM: it carves out, falls/deforms, and freezes back when settled. Usage: mpmthaw [radius]"],
        [floodviz,        "floodviz",  "Debug: flood connected solid terrain from your aim (biased down), colouring reached surface cells green. Non-blocking. Usage: floodviz [cells_per_frame]"],
        [perf,            "perf",      "Toggle the performance overlay (FPS + per-subsystem ms, bottom-right). Usage: perf [on|off]"],
        [awake,           "awake",     "Highlight awake physics bodies (debris / collapsed parts) with a box. Usage: awake [on|off]"],
        [reset,           "reset",     "Delete the save (EditStore blob + snapshot) and reload to a fresh world."],
        [quiescent,       "quiescent", "Print whether the world is quiescent (save-ready)."],
        [settle,          "settle",    "Force the world to rest so a save is never blocked (drains the support fixpoint)."],
        [parts,           "parts",     "Print the number of tracked parts."],
        [voxels,          "voxels",    "Print the number of tracked terrain voxels."],
        [tp,              "tp",        "Teleport the player. Usage: tp <x> <y> <z>"],
        [quit_game,       "quit_game", "Exit the game (separate from console's built-in quit)."],
    ]


# A console toggle's new state: empty arg flips `current`, otherwise "on" sets true.
func _parse_toggle(state: String, current: bool) -> bool:
    return not current if state == "" else state == "on"

func _terrain_material() -> ShaderMaterial:
    return load(VoxelConstants.TERRAIN_MATERIAL_PATH)

func set_uniform(param: String, value: float) -> void:
    var mat: ShaderMaterial = _terrain_material()
    if mat == null:
        LimboConsole.error("no terrain material")
        return
    mat.set_shader_parameter(param, value)   # one MeshInstance now — the change is live
    LimboConsole.info("%s = %s" % [param, value])

func get_uniform(pattern: String = "*") -> void:
    var mat: ShaderMaterial = _terrain_material()
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
    return {"terrain": _terrain_material(), "post": load(POST_MAT_PATH)}

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


func dcinval(_state := "") -> void:
    var on: bool = inval_overlay.toggle()
    if on:
        world_preview.refresh_diagnostic()   # show the LOD diagnostic from the current mesh now
    LimboConsole.info("dcinval: %s — red=triangle too big on screen, yellow=too small" % ("on" if on else "off"))

func fov(degrees: float) -> void:
    var cam := host.get_viewport().get_camera_3d()
    if cam == null:
        LimboConsole.error("fov: no active camera")
        return
    cam.fov = clampf(degrees, 1.0, 179.0)   # dcworld polls FOV each frame → auto re-mesh
    LimboConsole.info("fov: %.1f°" % cam.fov)

# Freeze the render so a defect holds still; fly through it (noclip) to inspect holes.
func examine(state := "") -> void:
    var on := _parse_toggle(state, not world_preview.is_enabled())
    world_preview.set_enabled(not on)
    player.set_examine_movement(on)
    LimboConsole.info("examine: %s — re-mesh %s, noclip fly %s" % [
        ("ON" if on else "off"), ("FROZEN" if on else "live"), ("on" if on else "off")])

# `dcworld` is THE terrain render (doc 17 P3): the world-fixed octree, 0.25 m, graded by the screen-error
# budget controller (eps_px self-tunes against frame time + mesh lag, ~100 ms target / 500 ms ceiling).
func dcworld(arg := "") -> void:
    if arg.is_valid_float():                       # `dcworld 256` → set coverage radius AND turn on
        world_preview.set_radius(arg.to_float())
        world_preview.set_enabled(true)
        LimboConsole.info("dcworld: on, %.0fm coverage @ %.2fm cells (budget-tuned eps)" % [
            world_preview.win_radius_m, world_preview.base_cell])
        return
    if arg == "" and world_preview.is_enabled():   # `dcworld` (no args) → print live stats
        LimboConsole.info("dcworld: on, %.0fm coverage, eps_px=%.1f, last job=%.0fms" % [
            world_preview.win_radius_m, world_preview._eps_px, world_preview._job_work_ms])
        return
    var on := _parse_toggle(arg, world_preview.is_enabled())   # `dcworld on|off` (empty → toggle)
    world_preview.set_enabled(on)
    LimboConsole.info("dcworld: %s (THE world-fixed render, %.0fm coverage @ %.2fm cells, budget-tuned eps)" % [
        "on" if on else "off", world_preview.win_radius_m, world_preview.base_cell])

# Set parallel accel-bake worker count, or print the last phase timing split.
func dcthreads(n := 0) -> void:
    if n > 0:
        world_preview.set_mesh_threads(n)
        LimboConsole.info("dcthreads: %d workers" % world_preview._mesher.get_thread_count())
    else:
        LimboConsole.info(world_preview.mesh_phase_report())


func remesh() -> void:
    world_preview.force_rebuild()
    LimboConsole.info("remesh: full dcworld rebuild queued — read `dcthreads` for the phase timing")

# Wall-clock cap (ms) on refine work per grow while the world blooms — "do as much as you can in X ms".
func dcrefine(ms := 0.0) -> void:
    if ms > 0.0:
        world_preview.refine_us = int(ms * 1000.0)
    LimboConsole.info("dcrefine: %.1f ms refine budget per grow while blooming (C/P) — higher = faster bloom, longer per-job latency" % (world_preview.refine_us / 1000.0))


func dcretain(m := -1.0) -> void:
    if m >= 0.0:
        world_preview.retain_margin_m = m
    LimboConsole.info("dcretain: %.0f m kept resident beyond the visible window (M) — turn/backtrack within it doesn't re-bloom" % world_preview.retain_margin_m)


func dcframebudget(ms := 0.0) -> void:
    if ms > 0.0:
        world_preview.set_frame_budget(ms)
    LimboConsole.info("dcframebudget: %.1f ms render budget (refines while < %.1f ms) — higher = more detail, lower fps" % [
        world_preview.frame_budget, world_preview.frame_budget * 0.5])

# How many edited leaves the store holds + its SDF at your position.
func editstore() -> void:
    var here := player.global_position
    LimboConsole.info("editstore: %d edited leaves; at you store=%.2f" % [
        edit_store.store.leaf_count(), edit_store.store.sample(here)])

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
    # Thaw into the world's wired MpmStructure (the same one save-gating + DetachmentScout see), not a
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
