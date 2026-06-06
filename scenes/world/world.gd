extends Node3D

@onready var _terrain:   VoxelLodTerrain     = $VoxelLodTerrain
@onready var _integrity: StructuralIntegrity = $StructuralIntegrity
@onready var _player:    CharacterBody3D     = $Player

# F2 path-b spike: our own DC mesh of a region, built from VoxelData on the main
# thread and rendered by us (proves we can mesh+render over godot_voxel's data).
var _spike_mesh: MeshInstance3D
var _octree_mesh: MeshInstance3D
var _lod_probe_mesh: MeshInstance3D
var _dc_manager: DCTerrainManager
var _pbd_demo: PbdDemo
var _pbd_structure: PbdStructure

# World-ready gate: gameplay + physics systems start inactive and resume on a
# WorldReadyEvent, so nothing acts on a half-streamed world. We poll the terrain
# (is_area_editable around the player) rather than pausing it — pausing the
# terrain would stall the very streaming we're waiting on. A timeout backstops a
# bad probe so the game can never freeze forever.
var _world_ready := false
var _ready_wait := 0.0
const READY_PROBE_RADIUS := 8.0      # cells around the player that must be loaded
const WORLD_READY_TIMEOUT := 10.0    # seconds; fire anyway past this


func _enter_tree() -> void:
    SavePaths.ensure_dir()
    # Keep generated data blocks resident (default off) so our region reads hit
    # cached data instead of re-running the noise generator every time. Set before
    # the terrain starts generating (parent _enter_tree runs before the child's).
    $VoxelLodTerrain.cache_generated_blocks = true
    # If a reset is pending, detach the SQLite stream BEFORE the terrain
    # node enters the tree, so it never reads modified blocks from disk.
    # _enter_tree runs parent-first, so we get here before $VoxelLodTerrain
    # has run its own _enter_tree.
    if WorldSnapshot.reset_pending:
        $VoxelLodTerrain.stream = null

func _ready() -> void:
    var resetting := WorldSnapshot.reset_pending
    WorldSnapshot.reset_pending = false
    if not resetting and SavePaths.snapshot_exists():
        if WorldSnapshot.load_into(SavePaths.SNAPSHOT_FILE, self):
            Toast.success("Loaded save.")
    _dc_manager = DCTerrainManager.new()
    add_child(_dc_manager)
    _dc_manager.setup(_terrain, _player)
    _dc_manager.start_default()   # DC is the default terrain render; dcmanager/dcsolo override
    _pbd_structure = PbdStructure.new()
    _pbd_structure.name = "PbdStructure"   # ActionFactories resolves the probe target by this name
    add_child(_pbd_structure)
    _pbd_structure.setup(_integrity)
    _integrity.pbd = _pbd_structure
    _pbd_structure.set_enabled(true)   # PBD is authoritative; the old collapse systems stand down
    _register_console_commands()

func _exit_tree() -> void:
    # Drop our console commands before this world is freed (scene reload / quit)
    # so LimboConsole never holds a callable bound to a freed object.
    _unregister_console_commands()


func _process(delta: float) -> void:
    if _world_ready:
        return
    _ready_wait += delta
    var timed_out := _ready_wait >= WORLD_READY_TIMEOUT
    if not _terrain_loaded_around_player() and not timed_out:
        return
    _world_ready = true
    if timed_out:
        push_warning("world_ready fired on timeout — terrain may not be fully streamed")
    VoxelEventBusSingleton.emit(WorldReadyEvent.CHANNEL, WorldReadyEvent.new())

# True once the terrain DATA (not just mesh) around the player has streamed in —
# the point at which gravity, edits, and PBD anchoring can trust the SDF.
func _terrain_loaded_around_player() -> bool:
    if _player == null or _terrain == null:
        return false
    var vt := _terrain.get_voxel_tool()
    var origin := _player.global_position - Vector3.ONE * READY_PROBE_RADIUS
    return vt.is_area_editable(AABB(origin, Vector3.ONE * (READY_PROBE_RADIUS * 2.0)))


# --- Console commands (Limbo) ---
#
# The LimboConsole autoload outlives this scene. On reload (F9 / reset) the old
# world is freed; a command left registered would point at a freed object and
# crash LimboConsole's introspection (get_method_list on a null value). So we
# register on _ready and unregister on _exit_tree, keeping bindings live. One
# command list feeds both so the names can't drift.
func _console_commands() -> Array:
    return [
        [_cmd_set,       "set",       "Set a terrain shader uniform (float). Usage: set <name> <value>"],
        [_cmd_get,       "get",       "List terrain shader uniforms matching a glob (default *). Usage: get [pattern]"],
        [_cmd_vdebug,    "vdebug",    "Toggle a VoxelLodTerrain debug overlay. Usage: vdebug [flag]; no arg lists flags."],
        [_cmd_dcspike,   "dcspike",   "F2 spike: DC-mesh a region around you from VoxelData and render it (magenta)."],
        [_cmd_dcoctree,  "dcoctree",  "F2 spike: octree-DC a region with a fine/coarse seam (multi-LOD, crack-free; cyan)."],
        [_cmd_dcmanager, "dcmanager", "Toggle the DC terrain manager (threaded re-mesh of a bubble around you). Usage: dcmanager [on|off]"],
        [_cmd_dcsolo,    "dcsolo",    "Data-only mode: hide godot_voxel's render so only our DC mesh shows (enables the manager). Usage: dcsolo [on|off]"],
        [_cmd_dclod,     "dclod",     "F2 probe: generate+DC-mesh a region at LOD n around you (generator-sourced coarse data). Usage: dclod [lod]"],
        [_cmd_pbddemo,   "pbddemo",   "PBD demo: spawn a live mass-spring structure (stress-coloured) to watch sag/fail. Usage: pbddemo [cantilever|bridge|tower] [size]"],
        [_cmd_pbdlive,   "pbdlive",   "Toggle live PBD stress viz over your REAL structures (viz-only). Usage: pbdlive [on|off]"],
        [_cmd_perf,      "perf",      "Toggle the performance overlay (FPS + per-subsystem ms, bottom-right). Usage: perf [on|off]"],
        [_cmd_lod,       "lod",       "Get/set terrain lod_distance (higher = LOD boundaries farther = less pop-in). Usage: lod [distance]"],
        [_cmd_reset,     "reset",     "Delete the save (terrain DB + snapshot) and reload to a fresh world."],
        [_cmd_quiescent, "quiescent", "Print whether the world is quiescent (save-ready)."],
        [_cmd_settle,    "settle",    "Force the world to rest so a save is never blocked (drains support, sleeps PBD + falling bodies)."],
        [_cmd_parts,     "parts",     "Print the number of tracked parts."],
        [_cmd_voxels,    "voxels",    "Print the number of tracked terrain voxels."],
        [_cmd_tp,        "tp",        "Teleport the player. Usage: tp <x> <y> <z>"],
        [_cmd_quit,      "quit_game", "Exit the game (separate from console's built-in quit)."],
    ]

func _register_console_commands() -> void:
    for c in _console_commands():
        if not LimboConsole.has_command(c[1]):
            LimboConsole.register_command(c[0], c[1], c[2])

func _unregister_console_commands() -> void:
    if not is_instance_valid(LimboConsole):
        return
    for c in _console_commands():
        if LimboConsole.has_command(c[1]):
            LimboConsole.unregister_command(c[1])

func _cmd_set(param: String, value: float) -> void:
    var mat := _terrain.material as ShaderMaterial
    if mat == null:
        LimboConsole.error("terrain has no ShaderMaterial")
        return
    mat.set_shader_parameter(param, value)
    _push_terrain_material(mat)
    LimboConsole.info("%s = %s" % [param, value])

# VoxelLodTerrain renders each mesh block with its own pooled COPY of the
# material (so blocks can carry per-block LOD uniforms); _terrain.material is
# only the template. Changing a uniform on the template doesn't touch the live
# copies. Re-assigning the material re-pools every block from the template —
# godot_voxel preserves only its own per-block uniforms across the copy, so our
# custom uniforms refresh from the template. The null hop defeats set_material's
# identity early-out (it ignores assignment of the same instance).
func _push_terrain_material(mat: ShaderMaterial) -> void:
    _terrain.material = null
    _terrain.material = mat

# VoxelLodTerrain.DebugDrawFlag indices (see voxel_lod_terrain.h). active_mesh_blocks
# draws a box per visually-active mesh block, coloured by LOD — overlapping boxes
# of different sizes at one spot mean several LODs are active there.
const _VDEBUG_FLAGS := {
    "octree_nodes":       0,
    "octree_bounds":      1,
    "mesh_updates":       2,
    "edit_boxes":         3,
    "volume_bounds":      4,
    "edited_blocks":      5,
    "modifier_bounds":    6,
    "active_mesh_blocks": 7,
    "viewer_clipboxes":   8,
    "loaded_blocks":      9,
    "active_blocks":      10,
    "voxel_metadata":     11,
}

func _cmd_vdebug(flag_name: String = "") -> void:
    if not _VDEBUG_FLAGS.has(flag_name):
        LimboConsole.info("flags: " + ", ".join(PackedStringArray(_VDEBUG_FLAGS.keys())))
        return
    var idx: int = _VDEBUG_FLAGS[flag_name]
    var enabled := not _terrain.debug_get_draw_flag(idx)
    _terrain.debug_set_draw_flag(idx, enabled)
    # Per-flag flags draw nothing unless the master debug renderer is enabled.
    # Keep it on while any flag is set, off when none remain.
    var any := false
    for flag in _VDEBUG_FLAGS:
        if _terrain.debug_get_draw_flag(_VDEBUG_FLAGS[flag]):
            any = true
            break
    _terrain.debug_set_draw_enabled(any)
    LimboConsole.info("vdebug %s = %s" % [flag_name, enabled])

func _cmd_get(pattern: String = "*") -> void:
    var mat := _terrain.material as ShaderMaterial
    if mat == null:
        LimboConsole.error("terrain has no ShaderMaterial")
        return
    var found := 0
    for prop in mat.get_property_list():
        var pname: String = prop.name
        if not pname.begins_with("shader_parameter/"):
            continue
        var uniform := pname.substr("shader_parameter/".length())
        if not uniform.matchn(pattern):
            continue
        # get_shader_parameter returns the override, or null when the uniform
        # is at its shader default (not yet set on this material).
        var v: Variant = mat.get_shader_parameter(uniform)
        LimboConsole.info("%s = %s" % [uniform, "(default)" if v == null else v])
        found += 1
    if found == 0:
        LimboConsole.info("no shader uniforms match '%s'" % pattern)

func _cmd_reset() -> void:
    # Save files are left untouched on disk. Next scene-reload runs with
    # `reset_pending = true`, which detaches the terrain stream (procedural
    # terrain regenerates) and skips the snapshot load. F9 afterwards
    # reloads the saved state normally.
    WorldSnapshot.reset_pending = true
    LimboConsole.info("Resetting to defaults — saves left intact. F9 to restore.")
    get_tree().reload_current_scene.call_deferred()

# F2 path-b proof: read a region's SDF straight from the terrain's voxel store
# (main thread, transient VoxelTool — no held ref, the pattern that didn't crash),
# mesh it with our GDScript DualContour, and render it ourselves. If the magenta
# surface matches the terrain where you stand, the "own meshing layer over
# godot_voxel's data" architecture is viable.
func _cmd_dcspike() -> void:
    const N := 24
    var origin := Vector3i(_player.global_position.round()) - Vector3i(N / 2, N / 2, N / 2)
    var vt := _terrain.get_voxel_tool()
    vt.set_channel(VoxelBuffer.CHANNEL_SDF)

    var dim := N + 1                       # DC needs corner samples (cells + 1)
    var data := PackedFloat32Array()
    data.resize(dim * dim * dim)
    var i := 0
    var solid := 0
    for z in dim:
        for y in dim:
            for x in dim:
                var v := vt.get_voxel_f(origin + Vector3i(x, y, z))
                data[i] = v
                if v < 0.0:
                    solid += 1
                i += 1

    var baked := SdfBaked.new(data, Vector3(origin), 1.0, Vector3i(dim, dim, dim))
    var mesh := DualContour.build_field(baked, Vector3i(N, N, N), Vector3(origin), 1.0)

    if _spike_mesh == null:
        _spike_mesh = MeshInstance3D.new()
        var m := StandardMaterial3D.new()
        m.albedo_color = Color(1.0, 0.0, 1.0, 0.55)
        m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        m.cull_mode = BaseMaterial3D.CULL_DISABLED
        _spike_mesh.material_override = m
        add_child(_spike_mesh)
    _spike_mesh.mesh = mesh

    var nverts := 0
    if mesh.get_surface_count() > 0:
        nverts = (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    LimboConsole.info("dcspike: %d^3 at %s — %d solid samples, %d verts" % [N, origin, solid, nverts])

# F2 core proof: octree-DC over a real terrain region with a deliberate LOD seam
# inside it (full depth in the -X half, one level coarser in the +X half). The
# SDF is baked once from VoxelData, then meshed with our crack-free adaptive
# OctreeDC. A seamless cyan surface that changes triangle density across the
# middle = multi-LOD meshing works on real data — the heart of the new system.
func _cmd_dcoctree() -> void:
    const DEPTH := 5
    var size := 1 << DEPTH                 # 32-voxel root cube
    var origin := Vector3i(_player.global_position.round()) - Vector3i(size / 2, size / 2, size / 2)
    var dim := size + 1                     # corner samples
    var t0 := Time.get_ticks_msec()
    var data := DCRegionReader.new().read_sdf_lod0(_terrain, origin, Vector3i(dim, dim, dim))
    var t_read := Time.get_ticks_msec() - t0
    if data.size() != dim * dim * dim:
        LimboConsole.error("dcoctree: read returned %d (expected %d)" % [data.size(), dim * dim * dim])
        return
    var solid := 0
    for v in data:
        if v < 0.0:
            solid += 1
    var baked := SdfBaked.new(data, Vector3.ZERO, 1.0, Vector3i(dim, dim, dim))

    var refine := func(center: Vector3, _s: float, depth: int) -> bool:
        return depth < (DEPTH if center.x < size / 2.0 else DEPTH - 1)
    var t1 := Time.get_ticks_msec()
    var mesh := OctreeDC.build_field(baked, DEPTH, refine)
    var t_mesh := Time.get_ticks_msec() - t1

    if _octree_mesh == null:
        _octree_mesh = MeshInstance3D.new()
        var m := StandardMaterial3D.new()
        m.albedo_color = Color(0.2, 1.0, 1.0, 0.55)
        m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        m.cull_mode = BaseMaterial3D.CULL_DISABLED
        _octree_mesh.material_override = m
        add_child(_octree_mesh)
    _octree_mesh.mesh = mesh
    _octree_mesh.global_position = Vector3(origin)

    var nverts := 0
    if mesh.get_surface_count() > 0:
        nverts = (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    LimboConsole.info("dcoctree: read %dms, mesh %dms — %d solid, %d verts (fine -X / coarse +X)" % [t_read, t_mesh, solid, nverts])

# Spawn a live PBD structural-physics demo in front of the player (stress-coloured
# lines; watch it sag and snap). Re-run to reset.
func _cmd_pbddemo(kind := "cantilever", size := 12) -> void:
    var fwd := -_player.global_transform.basis.z
    var base := Vector3i((_player.global_position + fwd * 6.0 + Vector3.UP * 4.0).round())
    var sim: PbdSim
    match kind:
        "bridge": sim = PbdDemo.bridge(base, size)
        "tower":  sim = PbdDemo.tower(base, size)
        _:        sim = PbdDemo.cantilever(base, size)
    if _pbd_demo == null:
        _pbd_demo = PbdDemo.new()
        add_child(_pbd_demo)
    _pbd_demo.set_sim(sim)
    LimboConsole.info("pbddemo: %s size %d (%d members)" % [kind, size, sim.member_count()])

# Toggle the performance overlay (FPS + per-subsystem ms). No arg flips it.
func _cmd_perf(state := "") -> void:
    var on := not Perf.is_shown() if state == "" else state == "on"
    Perf.set_shown(on)
    LimboConsole.info("perf: %s" % ("on" if on else "off"))

# Toggle live PBD stress viz over the player's real structures (viz-only). No arg flips.
func _cmd_pbdlive(state := "") -> void:
    var on := not _pbd_structure.is_enabled() if state == "" else state == "on"
    _pbd_structure.set_enabled(on)
    LimboConsole.info("pbdlive: %s" % ("on" if on else "off"))

# Toggle the always-on threaded DC terrain manager (path-b #3). No arg flips it.
func _cmd_dcmanager(state := "") -> void:
    var on := not _dc_manager.is_enabled() if state == "" else state == "on"
    _dc_manager.set_enabled(on)
    LimboConsole.info("dcmanager: %s" % ("on" if on else "off"))

# Probe: read terrain SDF at LOD n (edit-inclusive: generator baseline + edit mips)
# and DC-mesh it, to eyeball whether coarse data looks sensible at each LOD (the
# planned source for the clipmap's far levels). The mesh is built in lattice units
# and scaled by the LOD step so it lands at the right world size.
func _cmd_dclod(lod := 1) -> void:
    const DEPTH := 5                         # 32-cell uniform octree
    var step := 1 << clampi(lod, 0, 6)
    var dim := (1 << DEPTH) + 1              # corner samples
    var extent := (dim - 1) * step          # world size of the region
    var center := Vector3i(_player.global_position.round())
    var origin := center - Vector3i(extent / 2, extent / 2, extent / 2)
    origin = (origin / step) * step          # snap to the LOD grid
    var t0 := Time.get_ticks_msec()
    var data := DCRegionReader.new().read_sdf_lod(_terrain, lod, origin, Vector3i(dim, dim, dim))
    var t_read := Time.get_ticks_msec() - t0
    if data.size() != dim * dim * dim:
        LimboConsole.error("dclod: read returned %d (expected %d)" % [data.size(), dim * dim * dim])
        return
    var solid := 0
    for v in data:
        if v < 0.0:
            solid += 1
    var baked := SdfBaked.new(data, Vector3.ZERO, 1.0, Vector3i(dim, dim, dim))
    var t1 := Time.get_ticks_msec()
    var mesh := OctreeDC.build_field(baked, DEPTH)
    var t_mesh := Time.get_ticks_msec() - t1
    if _lod_probe_mesh == null:
        _lod_probe_mesh = MeshInstance3D.new()
        var m := StandardMaterial3D.new()
        m.albedo_color  = Color(1.0, 0.6, 0.1, 0.6)
        m.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
        m.cull_mode     = BaseMaterial3D.CULL_DISABLED
        _lod_probe_mesh.material_override = m
        add_child(_lod_probe_mesh)
    _lod_probe_mesh.mesh = mesh
    _lod_probe_mesh.scale = Vector3.ONE * step
    _lod_probe_mesh.global_position = Vector3(origin)
    LimboConsole.info("dclod %d: %dm region, read %dms, mesh %dms — %d solid samples" % [lod, extent, t_read, t_mesh, solid])

# Data-only mode: hide godot_voxel's render so only our DC mesh shows. Turning it
# on also enables the manager (no point hiding terrain with nothing replacing it).
func _cmd_dcsolo(state := "") -> void:
    var on := not _dc_manager.is_data_only() if state == "" else state == "on"
    if on:
        _dc_manager.set_enabled(true)
    _dc_manager.set_data_only(on)
    LimboConsole.info("dcsolo: %s (godot_voxel render %s)" % [("on" if on else "off"), ("hidden" if on else "shown")])

# Tune LOD pop-in live. lod_distance is the per-level switch distance; larger
# pushes every LOD boundary farther out (finer detail at range, more blocks).
func _cmd_lod(distance := -1.0) -> void:
    if distance > 0.0:
        _terrain.lod_distance = distance
    LimboConsole.info("lod_distance = %.1f, lod_count = %d" % [_terrain.lod_distance, _terrain.lod_count])

func _cmd_quiescent() -> void:
    LimboConsole.info("quiescent: %s" % _integrity.is_quiescent())

func _cmd_settle() -> void:
    _integrity.force_quiescent()
    LimboConsole.info("settled — quiescent: %s" % _integrity.is_quiescent())

func _cmd_parts() -> void:
    LimboConsole.info("parts: %d" % _integrity.part_support.part_registry.size())

func _cmd_voxels() -> void:
    LimboConsole.info("tracked voxels: %d" % _integrity.terrain_support.voxel_data.size())

func _cmd_tp(x: float, y: float, z: float) -> void:
    _player.global_position = Vector3(x, y, z)
    LimboConsole.info("teleported to %s" % _player.global_position)

func _cmd_quit() -> void:
    get_tree().quit()
