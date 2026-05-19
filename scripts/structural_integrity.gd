class_name StructuralIntegrity
extends Node

class PartData:
    var cells:       Array[Vector3i]
    var material:    Materials
    # World-space Y of the part's bottom face. Lets thin parts stack within a
    # single voxel cell — support detection uses this to order parts within a
    # shared cell, so removing a lower part correctly orphans the upper one.
    var placement_y: float
    # Current support value in [0.0, 1.0], recomputed each physics frame.
    # Propagates from terrain through supporter parts, losing material.decay
    # at each hop. When this drops at or below FALL_THRESHOLD the part starts
    # straining.
    var support:     float = 0.0
    func _init(p_cells: Array[Vector3i], p_mat: Materials, p_y: float) -> void:
        cells       = p_cells
        material    = p_mat
        placement_y = p_y

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
var part_registry: Dictionary[Node3D, PartData] = {}

# Reverse map for cell → parts. A cell can hold multiple parts when thin
# parts are stacked vertically (a 0.15m beam on top of a 0.012m board both
# occupy the same voxel cell). The Array preserves placement order; ordering
# by placement_y is the support-detection invariant.
# Key: Vector3i, Value: Array[Node3D]
var _cell_to_part: Dictionary = {}

# Accumulated unsupported seconds per Part; drives the Part strain window.
var _part_strain: Dictionary = {}  # Node3D → float

# The Part currently under the player's raycast, if any. Used to surface a
# soft support-color tint on Parts that aren't otherwise straining, so the
# player can see why a structure is or isn't safe before it actually fails.
var _hovered_part: Node3D = null

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
    _wake_falling_bodies()

func register_part(node: Node3D, cells: Array[Vector3i], material: Materials, placement_y: float) -> void:
    part_registry[node] = PartData.new(cells, material, placement_y)
    for cell in cells:
        if not _cell_to_part.has(cell):
            _cell_to_part[cell] = []
        _cell_to_part[cell].append(node)

func remove_part(node: Node3D) -> void:
    if not part_registry.has(node):
        return
    var data := part_registry[node]
    for cell in data.cells:
        if _cell_to_part.has(cell):
            _cell_to_part[cell].erase(node)
            if _cell_to_part[cell].is_empty():
                _cell_to_part.erase(cell)
        for neighbor in VoxelUtils.neighbors(cell):
            if voxel_data.has(neighbor) and not voxel_data[neighbor].dirty:
                voxel_data[neighbor].dirty = true
                dirty_queue.append(neighbor)
    part_registry.erase(node)
    _part_strain.erase(node)
    _wake_falling_bodies()

func has_part_cell(pos: Vector3i) -> bool:
    return _cell_to_part.has(pos)

func set_hovered_part(node: Node3D) -> void:
    _hovered_part = node

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

    _strain_pulse_phase += delta * VoxelConstants.STRAIN_PULSE_HZ * TAU

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
            # Untracked solid (natural terrain). Only counts as a supporter
            # if it's below or beside us — gravity flows down. The mass of
            # rock ABOVE a cave doesn't hold the ceiling up; it pushes down.
            # Without this gate, every ceiling cell sees the untracked solid
            # directly above it and short-circuits to FULL_SUPPORT, defeating
            # the entire cave-integrity gradient.
            if neighbor.y > pos.y:
                continue
            s = FULL_SUPPORT
        elif _cell_to_part.has(neighbor):
            # A placed Part occupies this neighbour cell. Take the best
            # support across the stack — this is what lets a wood pillar
            # hold up a stone ceiling.
            s = NO_SUPPORT
            for part_node in _cell_to_part[neighbor]:
                s = maxf(s, part_registry[part_node].support)
        else:
            continue
        best = maxf(best, s)

    return maxf(NO_SUPPORT, best - decay)


# --- Part support + collapse ---

func _tick_part_strain(delta: float) -> void:
    _recompute_part_support()

    var pulse              := 0.5 + 0.5 * sin(_strain_pulse_phase)
    var to_collapse: Array  = []
    for node in part_registry:
        var data    := part_registry[node]
        var hovered := node == _hovered_part
        if data.support > VoxelConstants.FALL_THRESHOLD:
            _part_strain.erase(node)
            _apply_part_visual(node, data.support, 0.0, 0.0, hovered)
        else:
            _part_strain[node]   = _part_strain.get(node, 0.0) + delta
            var progress: float  = _part_strain[node] / VoxelConstants.STRAIN_DURATION_SEC
            _apply_part_visual(node, data.support, progress, pulse, hovered)
            if _part_strain[node] >= VoxelConstants.STRAIN_DURATION_SEC:
                to_collapse.append(node)
    for node in to_collapse:
        _collapse_part(node)

# Walk parts bottom-up by placement_y so each supportee sees its supporter's
# freshly-computed value. Same shape as terrain propagation but cheap because
# we sort instead of needing a fixpoint — parts only depend on parts strictly
# below themselves.
func _recompute_part_support() -> void:
    var nodes := part_registry.keys()
    nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool:
        return part_registry[a].placement_y < part_registry[b].placement_y)
    for node in nodes:
        var data := part_registry[node]
        data.support = _calculate_part_support(node, data)

func _calculate_part_support(node: Node3D, data: PartData) -> float:
    var best          := NO_SUPPORT
    var has_supporter := false
    var support_y     := floori(data.placement_y - 0.001)

    # For tall parts (rotated onto their end, spanning multiple Y cells), only
    # the bottom row of footprint cells looks for support — the upper rows are
    # part of the part's own body, not supported surfaces.
    var min_cell_y := data.cells[0].y
    for cell in data.cells:
        if cell.y < min_cell_y:
            min_cell_y = cell.y

    for cell in data.cells:
        if cell.y != min_cell_y:
            continue
        var supporter := _direct_part_supporter(node, cell, data.placement_y)
        if supporter != null:
            best          = maxf(best, part_registry[supporter].support)
            has_supporter = true
            continue
        var support_cell := Vector3i(cell.x, support_y, cell.z)
        if _is_natural_terrain(support_cell):
            return FULL_SUPPORT
        if voxel_data.has(support_cell):
            best          = maxf(best, voxel_data[support_cell].support)
            has_supporter = true
    if not has_supporter:
        return NO_SUPPORT
    return maxf(NO_SUPPORT, best - data.material.decay)

# Returns the part with the highest placement_y strictly less than my_y,
# searched across my own cell (for thin stacks within one cell) and the
# cell directly below (for stacks that cross a voxel boundary). Returns
# null if no such part exists.
func _direct_part_supporter(self_node: Node3D, my_cell: Vector3i, my_y: float) -> Node3D:
    var best_y    := -INF
    var best_node: Node3D = null
    for cell in [my_cell, my_cell + Vector3i(0, -1, 0)]:
        if not _cell_to_part.has(cell):
            continue
        for other in _cell_to_part[cell]:
            if other == self_node:
                continue
            var other_y := part_registry[other].placement_y
            if other_y < my_y and other_y > best_y:
                best_y    = other_y
                best_node = other
    return best_node

func _apply_part_visual(node: Node3D, support: float, strain_progress: float, pulse: float, hovered: bool) -> void:
    var data := part_registry[node]
    for child in node.get_children():
        var mi := child as MeshInstance3D
        if mi == null:
            continue
        var degraded := support < FULL_SUPPORT - VoxelConstants.SUPPORT_EPSILON
        if not (degraded or strain_progress > 0.0 or hovered):
            mi.material_override = null
            continue
        var mat := mi.material_override as StandardMaterial3D
        if mat == null:
            mat = StandardMaterial3D.new()
            mi.material_override = mat
        # Albedo keeps the part's natural surface color (and, eventually, its
        # texture) visible. Strain feedback rides entirely on emission, which
        # adds colored light without replacing the surface.
        mat.albedo_color               = data.material.albedo
        mat.roughness                  = 0.85
        mat.emission_enabled           = true
        mat.emission                   = get_support_color(support)
        mat.emission_energy_multiplier = 0.5 + strain_progress * pulse * 0.6

func _wake_falling_bodies() -> void:
    for child in get_parent().get_children():
        var body := child as RigidBody3D
        if body != null and body.sleeping:
            body.sleeping = false

func _collapse_part(node: Node3D) -> void:
    _apply_part_visual(node, FULL_SUPPORT, 0.0, 0.0, false)

    var data := part_registry[node]
    var mass := float(data.cells.size())

    var body := RigidBody3D.new()
    body.mass          = mass
    body.continuous_cd = true
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
