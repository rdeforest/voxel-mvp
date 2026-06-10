class_name StructuralIntegrity
extends Node


var store:              EditStore   # SDF source (generator + edits); set by world.gd after the store exists

var terrain_support:    TerrainSupport
var part_support:       PartSupport
var pbd:                PbdStructure       # set by world.gd; folded into is_quiescent

var _strain_pulse_phase := 0.0

# When false, the old PartSupport strain/collapse stands down because PbdStructure
# owns part support + collapse. PBD sets this off whenever it's enabled. (Terrain
# collapse has no old system left — PBD is the only path — so there's no terrain
# flag; the support propagation that PBD's tracked-set expansion rides on still
# runs unconditionally.)
var part_collapse_enabled := true

# Inactive until the world finishes loading (WorldReadyEvent) — don't classify
# support or tick falling bodies against a half-streamed SDF.
var _active := false


func _ready() -> void:
    terrain_support    = TerrainSupport.new()
    part_support       = PartSupport.new(terrain_support, self)
    terrain_support.bind_part_support(part_support)


# world.gd injects the store once it exists (this Node's _ready runs first). Fans it out to
# the terrain_support's solidity checks and this node's falling-body classification.
func set_store(p_store: EditStore) -> void:
    store = p_store
    terrain_support.store = p_store

    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_world_mutated)
    VoxelEventBusSingleton.subscribe(PartRemovedEvent.CHANNEL,       _on_world_mutated)
    VoxelEventBusSingleton.subscribe(WorldReadyEvent.CHANNEL,        _on_world_ready)

func _exit_tree() -> void:
    # Break the TerrainSupport ↔ PartSupport reference cycle so the
    # RefCounted components can free cleanly. Bus subscriptions auto-clean
    # via WeakRef once the components' refcounts drop to zero.
    if terrain_support != null:
        terrain_support.bind_part_support(null)


func _physics_process(delta: float) -> void:
    if not _active:
        return
    var t0 := Time.get_ticks_usec()
    # Support propagation + cell registration: always — PBD's tracked-set expansion
    # rides on it (the suspended-mass discovery is gated on the scalar support).
    if not terrain_support.dirty_queue.is_empty():
        terrain_support.process_dirty_queue()

    if part_collapse_enabled:   # old part system; off whenever PBD is authoritative
        _strain_pulse_phase += delta * VoxelConstants.STRAIN_PULSE_HZ * TAU
        var pulse := 0.5 + 0.5 * sin(_strain_pulse_phase)
        part_support.tick_strain(delta, pulse)

    _tick_falling_bodies()
    Perf.report("Structural", (Time.get_ticks_usec() - t0) / 1000.0)


# --- Bus handlers ---

func _on_world_mutated(_event: VoxelEvent) -> void:
    wake_falling_bodies()

func _on_world_ready(_event: VoxelEvent) -> void:
    _active = true


# --- Queries (kept; not bus-routed) ---

func get_support(pos: Vector3i) -> float:
    return terrain_support.get_support(pos)

func has_part(node: Node3D) -> bool:
    return part_support.has_part(node)

func has_part_cell(pos: Vector3i) -> bool:
    return part_support.has_part_cell(pos)

func get_part_data(node: Node3D) -> PartData:
    return part_support.part_registry.get(node)


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
    if store == null:
        return
    for child in get_parent().get_children():
        var body := child as RigidBody3D
        if body == null or not body.has_meta("cell_offsets"):
            continue
        _classify_falling_body(body)

func _classify_falling_body(body: RigidBody3D) -> void:
    var offsets:   Array[Vector3] = body.get_meta("cell_offsets")
    var transform := body.global_transform
    var buried    := 0
    for offset in offsets:
        if _cell_at(transform * offset) < VoxelConstants.SDF_SOLID_THRESHOLD:
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

func _cell_at(world: Vector3) -> float:
    return store.sample(Vector3(floori(world.x), floori(world.y), floori(world.z)))

# Force the world to a settled state so a save is never blocked: drain the support
# fixpoint, sleep the PBD network in place, and sleep every falling body. The save
# stays honest (a genuinely-settled snapshot) rather than bypassing the gate.
func force_quiescent() -> void:
    var guard := 0
    while not terrain_support.dirty_queue.is_empty() and guard < 100000:
        terrain_support.process_dirty_queue()
        guard += 1
    if pbd != null:
        pbd.force_settle()
    for child in get_parent().get_children():
        var body := child as RigidBody3D
        if body != null:
            body.sleeping = true


func is_quiescent() -> bool:
    if not terrain_support.dirty_queue.is_empty():     return false
    if pbd != null and not pbd.is_settled():           return false
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
