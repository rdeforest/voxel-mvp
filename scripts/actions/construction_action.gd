class_name ConstructionAction
extends Action

var part:          Part
var placement_pos: Vector3    # world position for the scene instance (float Y = SDF surface)
var world_anchor:  Vector3i   # voxel-grid cell for footprint origin
var rotation:      int        # 0-3, each step = 90° around Y
var terrain:       VoxelLodTerrain
var integrity:     StructuralIntegrity
var player:        CharacterBody3D

var _cached_fp:   Array[Vector3i] = []
var _fp_computed: bool            = false

func _init(
    p_part:     Part,
    p_pos:      Vector3,
    p_anchor:   Vector3i,
    p_rotation: int,
    p_terrain:  VoxelLodTerrain,
    p_integ:    StructuralIntegrity,
    p_player:   CharacterBody3D,
) -> void:
    part          = p_part
    placement_pos = p_pos
    world_anchor  = p_anchor
    rotation      = p_rotation
    terrain       = p_terrain
    integrity     = p_integ
    player        = p_player

func validate() -> bool:
    var fp := _footprint()
    if fp.is_empty():
        return false

    if player != null and _footprint_aabb(fp).has_point(player.global_position):
        return false

    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    for cell in fp:
        var below := cell + Vector3i(0, -1, 0)
        if vt.get_voxel_f(below) < VoxelConstants.SDF_SOLID_THRESHOLD:
            return true
        if integrity.has_part_cell(below):
            return true

    return false

func execute() -> void:
    if part.scene == null:
        push_error("ConstructionAction.execute(): part.scene is null")
        return

    var instance: Node3D = part.scene.instantiate()
    instance.global_position  = placement_pos
    instance.rotation_degrees = Vector3(0.0, 90.0 * rotation, 0.0)
    terrain.get_parent().add_child(instance)

    integrity.register_part(instance, _footprint(), Materials.from_name(part.material_name))

# --- internals ---

func _footprint() -> Array[Vector3i]:
    if _fp_computed:
        return _cached_fp
    var local_fp := part.footprint if not part.footprint.is_empty() \
        else _local_footprint_from_scene()
    for cell in local_fp:
        _cached_fp.append(cell + world_anchor)
    _fp_computed = true
    return _cached_fp

func _local_footprint_from_scene() -> Array[Vector3i]:
    if part.scene == null:
        return []
    var instance := part.scene.instantiate()
    var aabb     := _union_mesh_aabbs(instance)
    instance.free()
    if rotation != 0:
        var rot := Transform3D(Basis.from_euler(Vector3.UP * deg_to_rad(90.0 * rotation)), Vector3.ZERO)
        aabb     = rot * aabb
    return VoxelUtils.footprint_from_aabb(aabb)

func _union_mesh_aabbs(node: Node) -> AABB:
    var result := AABB()
    var found  := false
    for child in node.get_children():
        if not child is MeshInstance3D:
            continue
        var child_aabb: AABB = child.transform * child.get_aabb()
        result = result.merge(child_aabb) if found else child_aabb
        found  = true
    return result

func _footprint_aabb(fp: Array[Vector3i]) -> AABB:
    var lo := Vector3(fp[0])
    var hi := lo + Vector3.ONE
    for cell in fp:
        lo = lo.min(Vector3(cell))
        hi = hi.max(Vector3(cell) + Vector3.ONE)
    return AABB(lo, hi - lo)
