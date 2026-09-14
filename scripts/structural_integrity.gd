class_name StructuralIntegrity
extends Node


var store:              EditStore   # SDF source (generator + edits); set by world.gd after the store exists

var terrain_support:    TerrainSupport
var mpm:                MpmStructure       # set by world.gd; the PB-MPM substrate (the structural sim)

# Inactive until the world finishes loading (WorldReadyEvent) — don't classify
# support against a half-streamed SDF.
var _active := false


func _ready() -> void:
    terrain_support = TerrainSupport.new()


# world.gd injects the store once it exists (this Node's _ready runs first). Fans it out to
# the terrain_support's solidity checks.
func set_store(p_store: EditStore) -> void:
    store = p_store
    terrain_support.store = p_store

    VoxelEventBusSingleton.subscribe(WorldReadyEvent.CHANNEL, _on_world_ready)


func _physics_process(_delta: float) -> void:
    if not _active:
        return
    var t0 := Time.get_ticks_usec()
    # Support propagation + cell registration: maintains the tracked voxel set the probe read-out
    # and suspended-mass discovery rely on, drained at TerrainSupport.PROPAGATION_BUDGET per frame.
    if not terrain_support.dirty_queue.is_empty():
        terrain_support.process_dirty_queue()
    Perf.report("Structural", (Time.get_ticks_usec() - t0) / 1000.0)


# --- Bus handlers ---

func _on_world_ready(_event: VoxelEvent) -> void:
    _active = true


# --- Queries (kept; not bus-routed) ---

func get_support(pos: Vector3i) -> float:
    return terrain_support.get_support(pos)


# --- Helpers ---

# Force the world to a settled state so a save is never blocked: drain the support fixpoint.
# The save stays honest (a genuinely-settled snapshot) rather than bypassing the gate.
func force_quiescent() -> void:
    var guard := 0
    while not terrain_support.dirty_queue.is_empty() and guard < 100000:
        terrain_support.process_dirty_queue()
        guard += 1


func is_quiescent() -> bool:
    if not terrain_support.dirty_queue.is_empty():     return false
    # MPM particles live in the C++ sim, not as RigidBody nodes. A save mid-thaw would persist the
    # carved hole without the in-flight material (particles aren't serialised) — gate until the
    # material has frozen back into the store.
    if mpm != null and mpm.active_count() > 0:         return false
    return true
