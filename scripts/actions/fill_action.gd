class_name FillAction
extends AdditiveAction

enum Shape { SPHERE }

var position:  Vector3
var radius:    float
var shape:     int  # Shape enum
var terrain:   VoxelLodTerrain


func _init(
    p_position:  Vector3,
    p_radius:    float,
    p_terrain:   VoxelLodTerrain,
    p_player:    CharacterBody3D,
    p_material:  StringName = &"Stone",
    p_shape:     int = Shape.SPHERE,
) -> void:
    position      = p_position
    radius        = p_radius
    shape         = p_shape
    terrain       = p_terrain
    player        = p_player
    material_name = p_material

func validate() -> bool:
    if player != null:
        var dist := player.global_position.distance_to(position)
        if dist <= radius + PLAYER_CLEARANCE:
            return false
    return true

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    if terrain == null:
        return p
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    var origin     := position - Vector3.ONE *  radius
    var dimensions :=            Vector3.ONE * (radius * 2.0)
    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(cell: Vector3i) -> void:
            if not VoxelUtils.is_in_sphere(Vector3(cell), position, radius):
                return
            if vt.get_voxel_f(cell) >= VoxelConstants.SDF_SOLID_THRESHOLD:
                p.solid.append(cell)
    )
    return p

func execute() -> void:
    if terrain == null:
        push_error("FillAction.execute(): no terrain")
        return

    # Freeze any falling bodies inside the fill volume *before* the SDF mutation lands,
    # so physics doesn't squirt them sideways on the next tick. The buried-body
    # classifier integrates them into the SDF the moment they're fully covered.
    _freeze_bodies_in_volume()

    var voxel_tool := terrain.get_voxel_tool()
    voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
    voxel_tool.mode    = VoxelTool.MODE_ADD
    voxel_tool.do_sphere(position, radius)

    var origin     := position - Vector3.ONE *  radius
    var dimensions :=            Vector3.ONE * (radius * 2.0)

    var added: Array = []
    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(pos: Vector3i) -> void:
            if VoxelUtils.is_in_sphere(Vector3(pos), position, radius):
                added.append(pos)
    )
    emit_added(added)

    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, origin, dimensions))


func _freeze_bodies_in_volume() -> void:
    var space  := terrain.get_world_3d().direct_space_state
    var sphere := SphereShape3D.new()
    sphere.radius = radius
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape              = sphere
    query.transform          = Transform3D(Basis(), position)
    query.collide_with_areas = false
    for hit in space.intersect_shape(query, 32):
        var body := hit.collider as RigidBody3D
        if body != null and not body.freeze:
            body.freeze = true
