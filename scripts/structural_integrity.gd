class_name StructuralIntegrity
extends Node

const NO_SUPPORT   = 0.0
const FULL_SUPPORT = 1.0

var terrain:            VoxelLodTerrain

var terrain_support:    TerrainSupport
var part_support:       PartSupport
var debug:              IntegrityDebug

var _collapse_detector: CollapseDetector
var _strain_pulse_phase := 0.0


func _ready() -> void:
    terrain            = get_parent().get_node("VoxelLodTerrain")
    terrain_support    = TerrainSupport.new(terrain)
    part_support       = PartSupport.new(terrain_support, self)
    terrain_support.bind_part_support(part_support)
    debug              = IntegrityDebug.new(terrain_support, self)
    _collapse_detector = CollapseDetector.new(terrain_support, self)

    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_world_mutated)
    VoxelEventBusSingleton.subscribe(PartRemovedEvent.CHANNEL,       _on_world_mutated)

func _exit_tree() -> void:
    # Break the TerrainSupport ↔ PartSupport reference cycle so the
    # RefCounted components can free cleanly. Bus subscriptions auto-clean
    # via WeakRef once the components' refcounts drop to zero.
    if terrain_support != null:
        terrain_support.bind_part_support(null)


func _physics_process(delta: float) -> void:
    var t0 := Time.get_ticks_usec()
    if not terrain_support.dirty_queue.is_empty():
        terrain_support.process_dirty_queue()
    else:
        _collapse_detector.step()

    _strain_pulse_phase += delta * VoxelConstants.STRAIN_PULSE_HZ * TAU
    var pulse := 0.5 + 0.5 * sin(_strain_pulse_phase)

    _collapse_detector.tick_pending(delta)
    part_support.tick_strain(delta, pulse)
    debug.update(pulse, _collapse_detector.get_straining_voxels())
    _tick_falling_bodies()
    Perf.report("Structural", (Time.get_ticks_usec() - t0) / 1000.0)


# --- Bus handlers ---

func _on_world_mutated(_event: VoxelEvent) -> void:
    wake_falling_bodies()


# --- Queries (kept; not bus-routed) ---

func get_support(pos: Vector3i) -> float:
    return terrain_support.get_support(pos)

func has_part(node: Node3D) -> bool:
    return part_support.has_part(node)

func has_part_cell(pos: Vector3i) -> bool:
    return part_support.has_part_cell(pos)

func get_part_data(node: Node3D) -> PartData:
    return part_support.part_registry.get(node)


# --- Debug ---

var debug_visuals_enabled: bool:
    get: return debug.enabled if debug != null else true
    set(value):
        if debug != null:
            debug.set_enabled(value)

func set_debug_visuals_enabled(value: bool) -> void:
    debug.set_enabled(value)


# --- Helpers ---

func wake_falling_bodies() -> void:
    for child in get_parent().get_children():
        var body := child as RigidBody3D
        if body != null and body.sleeping:
            body.sleeping = false

# Each frame, classify every falling body's relationship with the terrain
# SDF at its current pose. Partially-buried bodies freeze in place; fully-
# buried bodies integrate back into the SDF as tracked voxels.
func _tick_falling_bodies() -> void:
    if terrain == null:
        return
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    for child in get_parent().get_children():
        var body := child as RigidBody3D
        if body == null or not body.has_meta("cell_offsets"):
            continue
        _classify_falling_body(body, vt)

func _classify_falling_body(body: RigidBody3D, vt: VoxelTool) -> void:
    var offsets:   Array[Vector3] = body.get_meta("cell_offsets")
    var transform := body.global_transform
    var buried    := 0
    for offset in offsets:
        if _cell_at(transform * offset, vt) < VoxelConstants.SDF_SOLID_THRESHOLD:
            buried += 1
    if buried == offsets.size():
        _integrate_buried_body(body, offsets, transform)
        return
    if buried > 0:
        if not body.freeze:
            body.freeze = true
        return
    if body.freeze:
        body.freeze   = false
        body.sleeping = false

func _integrate_buried_body(body: RigidBody3D, offsets: Array[Vector3], transform: Transform3D) -> void:
    for offset in offsets:
        var world := transform * offset
        var cell  := Vector3i(floori(world.x), floori(world.y), floori(world.z))
        VoxelEventBusSingleton.emit(
            VoxelAddedEvent.CHANNEL,
            VoxelAddedEvent.new(0, cell, Materials.STONE))
    body.queue_free()

static func _cell_at(world: Vector3, vt: VoxelTool) -> float:
    return vt.get_voxel_f(Vector3i(floori(world.x), floori(world.y), floori(world.z)))

func is_quiescent() -> bool:
    if not terrain_support.dirty_queue.is_empty():     return false
    if not _collapse_detector.is_idle():               return false
    for child in get_parent().get_children():
        var body := child as RigidBody3D
        if body != null and not body.sleeping:         return false
    return true

const SUPPORT_COLOR_TIERS := [
    [0.75, Color(0.0, 0.3, 1.0)],
    [0.50, Color(0.0, 0.9, 0.2)],
    [0.30, Color(1.0, 0.9, 0.0)],
    [0.10, Color(1.0, 0.5, 0.0)],
    [0.00, Color(1.0, 0.1, 0.0)],
]
const SUPPORT_COLOR_FAILED := Color(0.5, 0.0, 0.0)

static func get_support_color(support: float) -> Color:
    for tier in SUPPORT_COLOR_TIERS:
        if support > tier[0]:
            return tier[1]
    return SUPPORT_COLOR_FAILED
