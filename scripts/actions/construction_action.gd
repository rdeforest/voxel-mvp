class_name ConstructionAction
extends Action

const GRID_ID = 0

var part:          Part
var placement_pos: Vector3    # world position for the rotated bottom-center
var world_anchor:  Vector3i   # voxel-grid cell for the click point
var rotation:      Vector3i   # 0-3 per axis (X, Y, Z), each step = 90°
var material_name: StringName # overrides part.material_name when non-empty
var terrain:       VoxelLodTerrain
var integrity:     StructuralIntegrity   # query path only (has_part_cell)
var player:        CharacterBody3D

var _cached_fp:   Array[Vector3i] = []
var _fp_computed: bool            = false

func _init(
    p_part:     Part,
    p_pos:      Vector3,
    p_anchor:   Vector3i,
    p_rotation: Vector3i,
    p_material: StringName,
    p_terrain:  VoxelLodTerrain,
    p_integ:    StructuralIntegrity,
    p_player:   CharacterBody3D,
) -> void:
    part          = p_part
    placement_pos = p_pos
    world_anchor  = p_anchor
    rotation      = p_rotation
    material_name = p_material
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
        if integrity.has_part_cell(cell):
            return true
        var below := cell + Vector3i(0, -1, 0)
        if vt.get_voxel_f(below) < VoxelConstants.SDF_SOLID_THRESHOLD:
            return true
        if integrity.has_part_cell(below):
            return true

    return false

func execute() -> void:
    var instance := part.instantiate(material_name)
    # The procedural body's local origin is the unrotated bottom-center. After
    # rotation, the new bottom and horizontal centroid no longer sit on that
    # origin — shift the instance so the rotated bottom lands at
    # placement_pos.y and the rotated centroid is over placement_pos.x/.z.
    var rotated := _rotated_local_aabb()
    var shift   := Vector3(
        -(rotated.position.x + rotated.size.x * 0.5),
         -rotated.position.y,
        -(rotated.position.z + rotated.size.z * 0.5)
    )
    instance.transform = Transform3D(_basis(), placement_pos + shift)
    terrain.get_parent().add_child(instance)

    VoxelEventBus.emit(
        PartAddedEvent.CHANNEL,
        PartAddedEvent.new(
            GRID_ID,
            instance,
            _footprint(),
            Materials.from_name(material_name),
            placement_pos.y,
            part))

# --- internals ---

func _basis() -> Basis:
    var b := Basis.IDENTITY
    b = b.rotated(Vector3.RIGHT,   rotation.x * PI * 0.5)
    b = b.rotated(Vector3.UP,      rotation.y * PI * 0.5)
    b = b.rotated(Vector3.FORWARD, rotation.z * PI * 0.5)
    return b

# AABB of the part in local space (bottom-anchored at Y=0, centered in X/Z),
# rotated around the local origin. The result generally has negative Y and
# off-center X/Z — the execute() shift compensates.
func _rotated_local_aabb() -> AABB:
    var dims     := part.dimensions
    var unrot    := AABB(Vector3(-dims.x * 0.5, 0.0, -dims.z * 0.5), dims)
    return Transform3D(_basis(), Vector3.ZERO) * unrot

func _footprint() -> Array[Vector3i]:
    if _fp_computed:
        return _cached_fp
    if not part.footprint.is_empty():
        # Hand-authored footprints are not rotated for now — no Schematic
        # currently uses them.
        for cell in part.footprint:
            _cached_fp.append(cell + world_anchor)
    else:
        var rotated := _rotated_local_aabb()
        # World AABB: rotated extents anchored so the bottom is at
        # placement_pos.y and the rotated centroid sits over placement_pos.x/.z.
        var world := AABB(
            Vector3(
                placement_pos.x - rotated.size.x * 0.5,
                placement_pos.y,
                placement_pos.z - rotated.size.z * 0.5
            ),
            rotated.size
        )
        _cached_fp = VoxelUtils.footprint_from_aabb(world)
    _fp_computed = true
    return _cached_fp

func _footprint_aabb(fp: Array[Vector3i]) -> AABB:
    var lo := Vector3(fp[0])
    var hi := lo + Vector3.ONE
    for cell in fp:
        lo = lo.min(Vector3(cell))
        hi = hi.max(Vector3(cell) + Vector3.ONE)
    return AABB(lo, hi - lo)
