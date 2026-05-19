class_name DigAction
extends Action

enum Shape { SPHERE }

var position:  Vector3
var radius:    float
var shape:     int  # Shape enum

var terrain:   VoxelLodTerrain
var integrity: StructuralIntegrity

func _init(
    p_position:  Vector3,
    p_radius:    float,
    p_terrain:   VoxelLodTerrain,
    p_integrity: StructuralIntegrity,
    p_shape:     int = Shape.SPHERE,
) -> void:
    position  = p_position
    radius    = p_radius
    shape     = p_shape
    terrain   = p_terrain
    integrity = p_integrity

func validate() -> bool:
    # Dig is always valid for now. Refusal cases (e.g. unbreakable materials)
    # come later.
    return true

func execute() -> void:
    if terrain == null:
        push_error("DigAction.execute(): no terrain")
        return

    var voxel_tool := terrain.get_voxel_tool()
    voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
    voxel_tool.mode    = VoxelTool.MODE_REMOVE
    voxel_tool.do_sphere(position, radius)

    var origin     := position - Vector3.ONE *  radius
    var dimensions :=            Vector3.ONE * (radius * 2.0)

    # Drop any tracked voxels now inside the dig sphere.
    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(pos: Vector3i):
            if VoxelUtils.is_in_sphere(Vector3(pos), position, radius):
                integrity.remove_voxel(pos)
    )

    # Register newly-exposed cave walls/ceiling: solid cells just outside the
    # dig sphere that now have at least one air neighbour. Without this, the
    # geometry of the cave is invisible to the structural integrity system —
    # the Phase 5 killer demo (wide cave → strain → reinforce with pillars)
    # depends on this registration.
    _register_exposed_cells(voxel_tool)

    integrity.notify_terrain_changed(position, radius)

func _register_exposed_cells(vt: VoxelTool) -> void:
    var expanded_origin     := position - Vector3.ONE * (radius + 1.0)
    var expanded_dimensions := Vector3.ONE * ((radius + 1.0) * 2.0)
    VoxelUtils.for_each_in_bounding_box(
        expanded_origin,
        expanded_dimensions,
        func(pos: Vector3i):
            if integrity.voxel_data.has(pos):
                return
            if vt.get_voxel_f(pos) >= VoxelConstants.SDF_SOLID_THRESHOLD:
                return
            for neighbor in VoxelUtils.neighbors(pos):
                if vt.get_voxel_f(neighbor) >= VoxelConstants.SDF_SOLID_THRESHOLD:
                    integrity.register_voxel(pos, Materials.STONE)
                    return
    )
