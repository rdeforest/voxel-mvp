class_name StructuralIntegrity
extends Node

const QUIESCE_PASS_LIMIT := 100000


var store:              EditStore   # SDF source (generator + edits); set by world.gd after the store exists

var terrain_support:    TerrainSupport
var mpm:                MpmStructure       # set by world.gd; the PB-MPM substrate (the structural sim)
var scout:              DetachmentScout    # registers itself in its setup; the loss-of-support trigger

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
    var t0 := Time.get_ticks_usec()
    tick()
    Perf.report("Structural", (Time.get_ticks_usec() - t0) / 1000.0)


# One physics frame of work. Support propagation + cell registration maintain the tracked voxel set
# the probe read-out and suspended-mass discovery rely on, drained at
# TerrainSupport.PROPAGATION_BUDGET per frame; the frame is that budget's unit, so a replay steps it
# on its own clock by calling this (test/support/scenario.gd), never on wall-clock time.
func tick() -> void:
    if not _active:
        return
    if not terrain_support.dirty_queue.is_empty():
        terrain_support.process_dirty_queue()


# --- Bus handlers ---

func _on_world_ready(_event: VoxelEvent) -> void:
    _active = true


# --- Queries (kept; not bus-routed) ---

func get_support(pos: Vector3i) -> float:
    return terrain_support.get_support(pos)


# --- Helpers ---

# Drain the support fixpoint now instead of at PROPAGATION_BUDGET per frame (console `settle`).
# Only support is fast-forwarded: the scout and MPM, which is_quiescent() also waits for, reach
# idle on their own over later physics frames. A queue still dirty after QUIESCE_PASS_LIMIT passes
# means propagation isn't converging — a defect to surface, not load to wait out — so it reports
# and returns false; the save gate then keeps refusing rather than capturing an unsettled world.
func force_quiescent() -> bool:
    var passes := 0
    while not terrain_support.dirty_queue.is_empty() and passes < QUIESCE_PASS_LIMIT:
        terrain_support.process_dirty_queue()
        passes += 1

    if terrain_support.dirty_queue.is_empty():
        return true

    push_error("StructuralIntegrity: support did not settle after %d passes; %d cells still dirty"
        % [QUIESCE_PASS_LIMIT, terrain_support.dirty_queue.size()])
    return false


# Nothing structural is mid-flight, so the save (or a recording's start) captures all of it: none of
# the work below is serialised. MPM particles live in the C++ sim; a save mid-thaw would persist the
# carved hole without the in-flight material, and one mid-freeze would miss the announcements that
# register the frozen pile. A detachment the scout hasn't resolved yet would be dropped outright.
func is_quiescent() -> bool:
    if not terrain_support.dirty_queue.is_empty():     return false
    if mpm != null and not mpm.is_idle():              return false
    if scout != null and not scout.is_idle():          return false
    return true
