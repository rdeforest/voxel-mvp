class_name FillAction
extends AdditiveAction

enum Shape { SPHERE }

var position:  Vector3
var radius:    float
var shape:     int  # Shape enum
var store:     EditStore


func _init(
    p_position:  Vector3,
    p_radius:    float,
    p_store:     EditStore,
    p_player:    CharacterBody3D,
    p_material:  StringName = &"Stone",
    p_shape:     int = Shape.SPHERE,
) -> void:
    position      = p_position
    radius        = p_radius
    shape         = p_shape
    store         = p_store
    player        = p_player
    material_name = p_material

func validate() -> bool:
    if player != null:
        var dist := player.global_position.distance_to(position)
        if dist <= radius + VoxelConstants.PLAYER_CLEARANCE:
            return false
    return true

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    if store == null:
        return p
    var origin     := position - Vector3.ONE *  radius
    var dimensions :=            Vector3.ONE * (radius * 2.0)
    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(cell: Vector3i) -> void:
            if not VoxelUtils.is_in_sphere(Vector3(cell), position, radius):
                return
            if store.sample(Vector3(cell)) >= VoxelConstants.SDF_SOLID_THRESHOLD:
                p.solid.append(cell)
    )
    return p

func execute() -> void:
    if store == null:
        push_error("FillAction.execute(): no store")
        return

    # Freeze any falling bodies inside the fill volume *before* the SDF mutation lands,
    # so physics doesn't squirt them sideways on the next tick. The buried-body
    # classifier integrates them into the SDF the moment they're fully covered.
    _freeze_bodies_in_volume()

    store.stamp_sphere(position, radius, VoxelConstants.STORE_OP_UNION,
        MaterialPalette.index_of(material_name), VoxelConstants.RENDER_BASE_CELL)

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
    if player == null:
        return
    var sphere := SphereShape3D.new()
    sphere.radius = radius
    PhysicsUtils.freeze_bodies_in(
        player.get_world_3d().direct_space_state, sphere, Transform3D(Basis(), position))
