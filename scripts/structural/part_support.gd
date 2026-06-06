class_name PartSupport
extends RefCounted

const NO_SUPPORT       = 0.0
const FULL_SUPPORT     = 1.0
const GRID_ID          = 0

# Stress emission visibility: parts only glow when the cursor is within
# PROXIMITY_RADIUS of any of the part's cells, OR support has dropped to
# the always-show threshold (orange tier or worse).
const PROXIMITY_RADIUS := 6.0
const ALWAYS_SHOW_MAX  := 0.30

var part_registry:    Dictionary[Node3D, PartData] = {}
var _cell_to_part:    Dictionary                   = {}
var _part_strain:     Dictionary                   = {}

var raycast:          RayCast3D                       # set externally (player._wire_debug_raycast)
var _terrain_support: TerrainSupport
var _facade:          Node


func _init(terrain_support: TerrainSupport, facade: Node) -> void:
    _terrain_support = terrain_support
    _facade          = facade
    VoxelEventBusSingleton.subscribe(PartAddedEvent.CHANNEL,   _on_part_added)
    VoxelEventBusSingleton.subscribe(PartRemovedEvent.CHANNEL, _on_part_removed)


# --- Bus handlers ---

func _on_part_added(event: PartAddedEvent) -> void:
    _register_part(event.node, event.cells, event.material, event.placement_y, event.part)

func _on_part_removed(event: PartRemovedEvent) -> void:
    _remove_part(event.node)


# --- Internal data ops (also called by snapshot restore) ---

func register_part(node: Node3D, cells: Array[Vector3i], material: Materials, placement_y: float, part: Part) -> void:
    _register_part(node, cells, material, placement_y, part)

func _register_part(node: Node3D, cells: Array[Vector3i], material: Materials, placement_y: float, part: Part) -> void:
    part_registry[node] = PartData.new(cells, material, placement_y, part)
    for cell in cells:
        if not _cell_to_part.has(cell):
            _cell_to_part[cell] = []
        _cell_to_part[cell].append(node)
        _terrain_support.dirty_neighbors_of(cell)

func _remove_part(node: Node3D) -> void:
    if not part_registry.has(node):
        return
    var data := part_registry[node]
    for cell in data.cells:
        if _cell_to_part.has(cell):
            _cell_to_part[cell].erase(node)
            if _cell_to_part[cell].is_empty():
                _cell_to_part.erase(cell)
        _terrain_support.dirty_neighbors_of(cell)
    part_registry.erase(node)
    _part_strain.erase(node)


# --- Queries ---

func has_part(node: Node3D) -> bool:
    return part_registry.has(node)

func has_cell(pos: Vector3i) -> bool:
    return _cell_to_part.has(pos)

func has_part_cell(pos: Vector3i) -> bool:
    return _cell_to_part.has(pos)

func best_support_at(cell: Vector3i) -> float:
    var best := NO_SUPPORT
    for part_node in _cell_to_part[cell]:
        best = maxf(best, part_registry[part_node].support)
    return best

# Parts occupying a cell (usually 0 or 1; intersection placement allows >1).
func parts_at_cell(cell: Vector3i) -> Array:
    return _cell_to_part.get(cell, [])


# --- Per-frame ---

func tick_strain(delta: float, pulse: float) -> void:
    _recompute_part_support()

    var pointer     := Vector3.ZERO
    var has_pointer := false
    if raycast != null and raycast.is_colliding():
        pointer     = raycast.get_collision_point()
        has_pointer = true

    var to_collapse: Array = []
    for node in part_registry:
        var data         := part_registry[node]
        var near_pointer := has_pointer and _is_part_near_pointer(data, pointer)
        if data.support > VoxelConstants.FALL_THRESHOLD:
            _part_strain.erase(node)
            _apply_visual(node, data.support, 0.0, 0.0, near_pointer)
        elif data.in_limbo:
            _apply_visual(node, data.support, 0.0, 0.0, near_pointer)
        else:
            _part_strain[node]   = _part_strain.get(node, 0.0) + delta
            var progress: float  = _part_strain[node] / VoxelConstants.STRAIN_DURATION_SEC
            _apply_visual(node, data.support, progress, pulse, near_pointer)
            if _part_strain[node] >= VoxelConstants.STRAIN_DURATION_SEC:
                to_collapse.append(node)
    for node in to_collapse:
        collapse_part(node)

func _is_part_near_pointer(data: PartData, pointer: Vector3) -> bool:
    var r2 := PROXIMITY_RADIUS * PROXIMITY_RADIUS
    for cell in data.cells:
        if (Vector3(cell) + Vector3.ONE * 0.5).distance_squared_to(pointer) < r2:
            return true
    return false


# --- Internals ---

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
    var any_dirty     := false
    var found_full    := false
    var support_y  := floori(data.placement_y - 0.001)
    var min_cell_y := _min_y(data.cells)

    for cell in data.cells:
        if cell.y != min_cell_y:
            continue
        var supporter := _direct_part_supporter(node, cell, data.placement_y)
        if supporter != null:
            var other := part_registry[supporter]
            best          = maxf(best, other.support)
            has_supporter = true
            if other.in_limbo:
                any_dirty = true
            continue
        var support_cell := Vector3i(cell.x, support_y, cell.z)
        if _terrain_support.is_natural_terrain(support_cell):
            found_full = true
            continue
        if _terrain_support.voxel_data.has(support_cell):
            var rec: VoxelRecord = _terrain_support.voxel_data[support_cell]
            best          = maxf(best, rec.support)
            has_supporter = true
            if rec.dirty:
                any_dirty = true

    data.in_limbo = any_dirty

    if found_full:
        return FULL_SUPPORT
    if not has_supporter:
        return NO_SUPPORT
    return maxf(NO_SUPPORT, best - data.material.decay)

static func _min_y(cells: Array[Vector3i]) -> int:
    var min_cell_y := cells[0].y
    for cell in cells:
        if cell.y < min_cell_y:
            min_cell_y = cell.y
    return min_cell_y

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

func _apply_visual(node: Node3D, support: float, strain_progress: float, pulse: float, near_pointer: bool) -> void:
    var data := part_registry[node]
    for child in node.get_children():
        var mi := child as MeshInstance3D
        if mi == null:
            continue
        var dangerous := support <= ALWAYS_SHOW_MAX
        if not (dangerous or strain_progress > 0.0 or near_pointer):
            mi.material_override = null
            continue
        var mat := mi.material_override as StandardMaterial3D
        if mat == null:
            mat = StandardMaterial3D.new()
            mi.material_override = mat
        mat.albedo_color               = data.material.albedo
        mat.roughness                  = 0.85
        mat.emission_enabled           = true
        mat.emission                   = StructuralIntegrity.get_support_color(support)
        mat.emission_energy_multiplier = 0.5 + strain_progress * pulse * 0.6

# Reparent a part's meshes to a fresh falling RigidBody3D and drop it from the
# registry. Driven by the old strain timer OR, when PBD is authoritative, by
# PbdStructure on detachment.
func collapse_part(node: Node3D) -> void:
    if not part_registry.has(node):
        return
    _apply_visual(node, FULL_SUPPORT, 0.0, 0.0, false)

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

    _remove_part(node)
    _facade.wake_falling_bodies()
