class_name StructuralIntegrity
extends Node

const NO_SUPPORT   = 0.0
const FULL_SUPPORT = 1.0

# Emitted from the propagation loop whenever a voxel's recalculated support is
# meaningfully *higher* than its previous value. This is the "the player did
# something that helped" signal. CollapseDetector listens for it to reset the
# strain timer of any pending collapse the voxel belongs to.
#
# Emitted at the moment of evaluation, by the code that already holds both the
# old and new values — no polling, no per-voxel history kept anywhere.
signal voxel_support_increased(pos: Vector3i, old_support: float, new_support: float)

# Per-voxel data for modified regions only
# Key: Vector3i, Value: { support: float, material: String, dirty: bool, structure_id: int }
var voxel_data: Dictionary = {}

# Queue of dirty voxels needing recalculation
var dirty_queue: Array[Vector3i] = []

var _collapse_detector: CollapseDetector

# Reference to terrain
var terrain: VoxelLodTerrain

func _ready() -> void:
    terrain = get_parent().get_node("VoxelLodTerrain")
    _collapse_detector = CollapseDetector.new(self)

# --- Public API ---

func register_voxel(pos: Vector3i, material: Materials) -> void:
    voxel_data[pos] = {
        "support":      NO_SUPPORT,
        "material":     material,
        "dirty":        true,
        "structure_id": 0, # XXX: not used yet
    }
    dirty_queue.append(pos)

func remove_voxel(pos: Vector3i) -> void:
    voxel_data.erase(pos)
    # Mark all neighbors as dirty
    for neighbor in _get_neighbors(pos):
        if voxel_data.has(neighbor):
            voxel_data[neighbor].dirty = true
            dirty_queue.append(neighbor)

func get_support(pos: Vector3i) -> float:
    if voxel_data.has(pos):
        return voxel_data[pos].support
    # Untracked voxels are either air (irrelevant) or
    # unmodified terrain (fully supported)
    return FULL_SUPPORT

func get_support_color(support: float) -> Color:
    # Blue (1.0) -> Green (0.75) -> Yellow (0.5) -> Orange (0.3) -> Red (0.1) -> Dark Red (0.0)
    if support > 0.75:
        return Color(0.0, 0.3, 1.0)   # Blue - grounded
    elif support > 0.5:
        return Color(0.0, 0.9, 0.2)   # Green - solid
    elif support > 0.3:
        return Color(1.0, 0.9, 0.0)   # Yellow - moderate
    elif support > 0.1:
        return Color(1.0, 0.5, 0.0)   # Orange - weak
    elif support > 0.0:
        return Color(1.0, 0.1, 0.0)   # Red - failing
    else:
        return Color(0.5, 0.0, 0.0)   # Dark red - unsupported

# --- Propagation ---

func _physics_process(delta: float) -> void:
    if not dirty_queue.is_empty():
        _process_dirty_queue()
    else:
        # Propagation has settled. Scan for new collapses.
        _collapse_detector.step()

    # Strain must accumulate every frame regardless of dirty-queue state.
    # If a steady drip of edits kept the queue non-empty, gating this behind
    # "queue settled" would freeze every strain window indefinitely.
    _collapse_detector.tick_pending(delta)

    update_debug_visuals()


# Drain up to PROPAGATION_BUDGET voxels from the dirty queue, recalculating
# each one's support. A meaningful *change* re-dirties neighbours so the
# wave propagates; a meaningful *increase* additionally emits
# voxel_support_increased so a pending collapse can rewind its strain.
#
# This is a worklist fixpoint algorithm — the same shape compilers use for
# dataflow analysis. The support values form a lattice (floats in [0,1]),
# _calculate_support is the transfer function, _get_neighbors defines the
# dependency edges, and dirty_queue is the worklist. We iterate until the
# queue drains (the fixpoint). If propagation, fatigue, fluid, or temperature
# ever share enough of this machinery, the extract-worthy core is: queue,
# pop, recompute, "did it change", push dependents — with the transfer and
# dependency functions passed in. Not extracted yet: one customer, no second
# use case to generalise against.
func _process_dirty_queue() -> void:
    var processed := 0

    while not dirty_queue.is_empty() and processed < VoxelConstants.PROPAGATION_BUDGET:
        var pos : Vector3i = dirty_queue.pop_front()

        if not voxel_data.has(pos):
            continue
        if not voxel_data[pos].dirty:
            continue

        var old_support: float = voxel_data[pos].support
        var new_support := _calculate_support(pos)
        voxel_data[pos].support = new_support
        voxel_data[pos].dirty = false

        # If support changed significantly, dirty the neighbors
        if absf(new_support - old_support) > VoxelConstants.SUPPORT_EPSILON:
            for neighbor in _get_neighbors(pos):
                if voxel_data.has(neighbor) and not voxel_data[neighbor].dirty:
                    voxel_data[neighbor].dirty = true
                    dirty_queue.append(neighbor)

        # If support went *up* meaningfully, announce it. A pending
        # collapse containing this voxel will rewind its strain.
        # Emitted here because this is the one place that holds both
        # the old and new values; no history is kept anywhere.
        if new_support - old_support > VoxelConstants.SUPPORT_EPSILON:
            voxel_support_increased.emit(pos, old_support, new_support)

        processed += 1

func _calculate_support(pos: Vector3i) -> float:
    var data:     Dictionary = voxel_data[pos]
    var material: Materials  = data.material
    var decay:    float      = material.decay

    # Check if this voxel is ground-contact
    # (has a solid untracked voxel below it, i.e. natural terrain)
    var below := pos + Vector3i(0, -1, 0)
    if _is_natural_terrain(below):
        return FULL_SUPPORT

    # Find the best support from any neighbor
    var best_neighbor_support := NO_SUPPORT
    for neighbor in _get_neighbors(pos):
        var neighbor_support: float
        if voxel_data.has(neighbor):
            neighbor_support = voxel_data[neighbor].support
        elif _is_terrain_solid(neighbor):
            neighbor_support = FULL_SUPPORT
        else:
            continue

        best_neighbor_support = maxf(best_neighbor_support, neighbor_support)

    # Support = best neighbor's support minus our material's decay
    return maxf(NO_SUPPORT, best_neighbor_support - decay)

# --- Helpers ---

func _get_neighbors(pos: Vector3i) -> Array[Vector3i]:
    return [
        pos + Vector3i( 1,  0,  0),
        pos + Vector3i(-1,  0,  0),
        pos + Vector3i( 0,  1,  0),
        pos + Vector3i( 0, -1,  0),
        pos + Vector3i( 0,  0,  1),
        pos + Vector3i( 0,  0, -1),
    ]

func _is_natural_terrain(pos: Vector3i) -> bool:
    if voxel_data.has(pos):
        return false # placed material
    return _is_terrain_solid(pos)

func _is_terrain_solid(pos: Vector3i) -> bool:
    if terrain == null:
        return false
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    var sdf := vt.get_voxel_f(pos)
    return sdf < VoxelConstants.SDF_SOLID_THRESHOLD  # Negative SDF = inside solid terrain

# Debug visualization
var debug_meshes: Dictionary = {}  # Vector3i -> MeshInstance3D
const DEBUG_VOXEL_SIZE := 0.3

# Master switch for the debug voxel markers. Exported so it can be flipped in
# the inspector; also toggleable at runtime via set_debug_visuals_enabled()
# (wire that to a key in the player controller).
#
# These coloured cubes are a v0.0 development aid, not a real game visual —
# the roadmap's intent is for strain feedback to eventually live on the
# terrain surface geometry itself. Until then, this lets you get them out of
# the way when they're more clutter than signal.
@export var debug_visuals_enabled: bool = true

# Advancing phase for the strain pulse, in radians. Shared across all
# straining voxels so they pulse in unison — a synchronized creak reads as
# "this whole mass is in trouble" rather than visual noise.
var _strain_pulse_phase := 0.0


# Runtime toggle. When turned off, existing markers are torn down immediately
# so nothing is left floating; when turned back on, update_debug_visuals()
# rebuilds them on the next frame from current voxel_data.
func set_debug_visuals_enabled(enabled: bool) -> void:
    if enabled == debug_visuals_enabled:
        return
    debug_visuals_enabled = enabled
    if not enabled:
        _clear_debug_meshes()


# Tear down every debug marker and forget them. Used when debug visuals are
# switched off; the markers are rebuilt from scratch if switched back on.
func _clear_debug_meshes() -> void:
    for pos in debug_meshes:
        debug_meshes[pos].queue_free()
    debug_meshes.clear()


func update_debug_visuals() -> void:
    # When disabled, do no per-voxel work at all. Markers (if any) were already
    # torn down by set_debug_visuals_enabled(); this just makes the disabled
    # state cost nothing per frame.
    if not debug_visuals_enabled:
        return

    # Advance the shared strain-pulse phase. get_physics_process_delta_time()
    # is the fixed physics step; update_debug_visuals is only ever called from
    # _physics_process so this is the correct delta.
    _strain_pulse_phase += get_physics_process_delta_time() \
        * VoxelConstants.STRAIN_PULSE_HZ * TAU
    # Oscillates 0..1; multiplies into marker alpha for straining voxels.
    var pulse := 0.5 + 0.5 * sin(_strain_pulse_phase)

    # Which voxels are mid-strain right now. Pending-collapse voxels pulse;
    # everything else uses steady alpha.
    var straining: Dictionary = _collapse_detector.get_straining_voxels()

    # Remove markers for voxels that no longer exist
    for pos in debug_meshes.keys():
        if not voxel_data.has(pos):
            debug_meshes[pos].queue_free()
            debug_meshes.erase(pos)

    # Update or create markers for tracked voxels
    for pos in voxel_data:
        var support: float = voxel_data[pos].support
        var color := get_support_color(support)

        # Straining voxels pulse their alpha; steady voxels sit at 0.6.
        if straining.has(pos):
            color.a = lerpf(0.15, 0.9, pulse)
        else:
            color.a = 0.6

        if debug_meshes.has(pos):
            # Update existing marker color
            var mat: StandardMaterial3D = debug_meshes[pos].material_override
            mat.albedo_color = color
        else:
            # Create new marker
            var mi := MeshInstance3D.new()
            var box := BoxMesh.new()
            box.size = Vector3.ONE * DEBUG_VOXEL_SIZE
            mi.mesh = box

            var mat := StandardMaterial3D.new()
            mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            mat.no_depth_test = true
            mat.albedo_color = color
            mi.material_override = mat

            mi.global_position = Vector3(pos) + Vector3.ONE * 0.5
            add_child(mi)
            debug_meshes[pos] = mi
