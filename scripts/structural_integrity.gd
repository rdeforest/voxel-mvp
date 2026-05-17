class_name StructuralIntegrity
extends Node

class PartData:
    var cells:    Array[Vector3i]
    var material: Materials
    func _init(p_cells: Array[Vector3i], p_mat: Materials) -> void:
        cells    = p_cells
        material = p_mat

const NO_SUPPORT   = 0.0
const FULL_SUPPORT = 1.0

# Emitted from the propagation loop whenever a voxel's recalculated support is
# meaningfully *higher* than its previous value. CollapseDetector listens for
# it to reset the strain timer of any pending terrain collapse the voxel belongs to.
signal voxel_support_increased(pos: Vector3i, old_support: float, new_support: float)

# Terrain voxels modified by the player (filled or affected by collapse).
# Key: Vector3i, Value: { support: float, material: Materials, dirty: bool }
var voxel_data: Dictionary = {}

# Queue of dirty terrain voxels needing support recalculation.
var dirty_queue: Array[Vector3i] = []

# Placed scene-based parts. Key: Node3D (the scene root), Value: PartData
var part_registry: Dictionary = {}

# Reverse map for O(1) cell → Part lookup.
# Key: Vector3i, Value: Node3D
var _cell_to_part: Dictionary = {}

# Accumulated unsupported seconds per Part; drives the Part strain window.
var _part_strain: Dictionary = {}  # Node3D → float

var _collapse_detector: CollapseDetector
var terrain:            VoxelLodTerrain

func _ready() -> void:
    terrain = get_parent().get_node("VoxelLodTerrain")
    _collapse_detector = CollapseDetector.new(self)


# --- Public API ---

func register_voxel(pos: Vector3i, material: Materials) -> void:
    voxel_data[pos] = {
        "support":  NO_SUPPORT,
        "material": material,
        "dirty":    true,
    }
    dirty_queue.append(pos)

func remove_voxel(pos: Vector3i) -> void:
    voxel_data.erase(pos)
    for neighbor in VoxelUtils.neighbors(pos):
        if voxel_data.has(neighbor) and not voxel_data[neighbor].dirty:
            voxel_data[neighbor].dirty = true
            dirty_queue.append(neighbor)

func notify_terrain_changed(center: Vector3, radius: float) -> void:
    var expanded := radius + 1.0
    for pos in voxel_data:
        if Vector3(pos).distance_to(center) <= expanded and not voxel_data[pos].dirty:
            voxel_data[pos].dirty = true
            dirty_queue.append(pos)

func register_part(node: Node3D, cells: Array[Vector3i], material: Materials) -> void:
    part_registry[node] = PartData.new(cells, material)
    for cell in cells:
        _cell_to_part[cell] = node

func remove_part(node: Node3D) -> void:
    if not part_registry.has(node):
        return
    var data := part_registry[node] as PartData
    for cell in data.cells:
        _cell_to_part.erase(cell)
        for neighbor in VoxelUtils.neighbors(cell):
            if voxel_data.has(neighbor) and not voxel_data[neighbor].dirty:
                voxel_data[neighbor].dirty = true
                dirty_queue.append(neighbor)
    part_registry.erase(node)
    _part_strain.erase(node)

func has_part_cell(pos: Vector3i) -> bool:
    return _cell_to_part.has(pos)

func get_support(pos: Vector3i) -> float:
    if voxel_data.has(pos):
        return voxel_data[pos].support
    return FULL_SUPPORT

func get_support_color(support: float) -> Color:
    if support > 0.75: return Color(0.0, 0.3, 1.0)
    if support > 0.50: return Color(0.0, 0.9, 0.2)
    if support > 0.30: return Color(1.0, 0.9, 0.0)
    if support > 0.10: return Color(1.0, 0.5, 0.0)
    if support > 0.00: return Color(1.0, 0.1, 0.0)
    return                     Color(0.5, 0.0, 0.0)


# --- Per-frame update ---

func _physics_process(delta: float) -> void:
    if not dirty_queue.is_empty():
        _process_dirty_queue()
    else:
        _collapse_detector.step()

    _collapse_detector.tick_pending(delta)
    _tick_part_strain(delta)
    update_debug_visuals()


# --- Terrain propagation ---

# Worklist fixpoint: drain up to PROPAGATION_BUDGET voxels from dirty_queue,
# recalculating each one's support. A meaningful change re-dirties neighbours
# so the wave propagates; a meaningful increase emits voxel_support_increased
# so a pending terrain collapse can rewind its strain.
func _process_dirty_queue() -> void:
    var processed := 0

    while not dirty_queue.is_empty() and processed < VoxelConstants.PROPAGATION_BUDGET:
        var pos: Vector3i = dirty_queue.pop_back()

        if not voxel_data.has(pos):
            continue
        if not voxel_data[pos].dirty:
            continue

        var old_support: float = voxel_data[pos].support
        var new_support := _calculate_support(pos)
        voxel_data[pos].support = new_support
        voxel_data[pos].dirty   = false

        if absf(new_support - old_support) > VoxelConstants.SUPPORT_EPSILON:
            for neighbor in VoxelUtils.neighbors(pos):
                if voxel_data.has(neighbor) and not voxel_data[neighbor].dirty:
                    voxel_data[neighbor].dirty = true
                    dirty_queue.append(neighbor)

        if new_support - old_support > VoxelConstants.SUPPORT_EPSILON:
            voxel_support_increased.emit(pos, old_support, new_support)

        processed += 1

func _calculate_support(pos: Vector3i) -> float:
    var material: Materials = voxel_data[pos].material
    var decay:    float     = material.decay

    if _is_natural_terrain(pos + Vector3i(0, -1, 0)):
        return FULL_SUPPORT

    var best := NO_SUPPORT
    for neighbor in VoxelUtils.neighbors(pos):
        var s: float
        if voxel_data.has(neighbor):
            s = voxel_data[neighbor].support
        elif _is_terrain_solid(neighbor):
            s = FULL_SUPPORT
        else:
            continue
        best = maxf(best, s)

    return maxf(NO_SUPPORT, best - decay)


# --- Part support + collapse ---

func _is_part_supported(node: Node3D) -> bool:
    var data := part_registry[node] as PartData
    for cell in data.cells:
        var below := cell + Vector3i(0, -1, 0)
        if _is_natural_terrain(below):
            return true
        if voxel_data.has(below) and voxel_data[below].support > VoxelConstants.FALL_THRESHOLD:
            return true
        if _cell_to_part.has(below) and _cell_to_part[below] != node:
            return true
    return false

func _tick_part_strain(delta: float) -> void:
    var to_collapse: Array = []
    for node in part_registry:
        if _is_part_supported(node):
            _part_strain.erase(node)
        else:
            _part_strain[node] = _part_strain.get(node, 0.0) + delta
            if _part_strain[node] >= VoxelConstants.STRAIN_DURATION_SEC:
                to_collapse.append(node)
    for node in to_collapse:
        _collapse_part(node)

func _collapse_part(node: Node3D) -> void:
    var data := part_registry[node] as PartData
    var mass := float(data.cells.size())

    var body := RigidBody3D.new()
    body.can_sleep    = false
    body.mass         = mass
    node.get_parent().add_child(body)
    body.global_transform = node.global_transform
    for child in node.get_children():
        child.reparent(body)
    node.queue_free()

    remove_part(node)


# --- Helpers ---

func _is_natural_terrain(pos: Vector3i) -> bool:
    if voxel_data.has(pos):
        return false
    return _is_terrain_solid(pos)

func _is_terrain_solid(pos: Vector3i) -> bool:
    if terrain == null:
        return false
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    return vt.get_voxel_f(pos) < VoxelConstants.SDF_SOLID_THRESHOLD


# --- Debug visualization ---

var debug_meshes: Dictionary = {}
const DEBUG_VOXEL_SIZE := 0.3

@export var debug_visuals_enabled: bool = true

var _strain_pulse_phase := 0.0

func set_debug_visuals_enabled(enabled: bool) -> void:
    if enabled == debug_visuals_enabled:
        return
    debug_visuals_enabled = enabled
    if not enabled:
        _clear_debug_meshes()

func _clear_debug_meshes() -> void:
    for pos in debug_meshes:
        debug_meshes[pos].queue_free()
    debug_meshes.clear()

func update_debug_visuals() -> void:
    if not debug_visuals_enabled:
        return

    _strain_pulse_phase += get_physics_process_delta_time() * VoxelConstants.STRAIN_PULSE_HZ * TAU
    var pulse := 0.5 + 0.5 * sin(_strain_pulse_phase)

    var straining: Dictionary = _collapse_detector.get_straining_voxels()

    for pos in debug_meshes.keys():
        if not voxel_data.has(pos):
            debug_meshes[pos].queue_free()
            debug_meshes.erase(pos)

    for pos in voxel_data:
        var support: float = voxel_data[pos].support
        var color          := get_support_color(support)
        color.a = lerpf(0.15, 0.9, pulse) if straining.has(pos) else 0.6

        if debug_meshes.has(pos):
            (debug_meshes[pos].material_override as StandardMaterial3D).albedo_color = color
        else:
            var box := BoxMesh.new()
            box.size = Vector3.ONE * DEBUG_VOXEL_SIZE

            var mat := StandardMaterial3D.new()
            mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            mat.no_depth_test = true
            mat.albedo_color  = color

            var mi := MeshInstance3D.new()
            mi.mesh              = box
            mi.material_override = mat
            mi.global_position   = Vector3(pos) + Vector3.ONE * 0.5
            add_child(mi)
            debug_meshes[pos] = mi
