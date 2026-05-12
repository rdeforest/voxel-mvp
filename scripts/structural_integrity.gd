class_name StructuralIntegrity
extends Node

const NO_SUPPORT   = 0.0
const FULL_SUPPORT = 1.0

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

func _physics_process(_delta: float) -> void:
    if not dirty_queue.is_empty():
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

            processed += 1
    else:
        # Propagation has settled. Check for collapses.
        _collapse_detector.step()

    update_debug_visuals()

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

func update_debug_visuals() -> void:
    # Remove markers for voxels that no longer exist
    for pos in debug_meshes.keys():
        if not voxel_data.has(pos):
            debug_meshes[pos].queue_free()
            debug_meshes.erase(pos)

    # Update or create markers for tracked voxels
    for pos in voxel_data:
        var support: float = voxel_data[pos].support
        var color := get_support_color(support)

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
            mat.albedo_color = color
            mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            mat.no_depth_test = true
            color.a = 0.6
            mat.albedo_color = color
            mi.material_override = mat

            mi.global_position = Vector3(pos) + Vector3.ONE * 0.5
            add_child(mi)
            debug_meshes[pos] = mi
