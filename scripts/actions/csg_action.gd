class_name CsgAction
extends AdditiveAction

# Stamps an analytic CSG primitive (box / cylinder / sphere) into the terrain SDF
# so the zero-crossing is the exact mathematical surface — a known field to audit
# the Dual Contouring mesh against. The shape's signed distance (CsgSdf, negative
# inside) is combined with the existing terrain per cell:
#   ADD      (union)        new = min(existing,  d)
#   SUBTRACT (difference)   new = max(existing, -d)
# evaluated at the integer lattice points the mesher reads, over the shape's
# rotated AABB plus a margin so the surface band is written on every side.

const MARGIN  := 2.0   # cells of band written beyond the shape, for a clean crossing


var shape:    int
var dims:     Vector3
var xform:    Transform3D   # shape local -> world (rotation basis + placement origin)
var op:       int           # CsgState.Op

var terrain:  VoxelLodTerrain

# Cached work: [[Vector3i cell, float new_sdf, bool was_solid, bool now_solid], ...]
var _work: Array         = []
var _work_computed: bool = false


func _init(
    p_shape:    int,
    p_dims:     Vector3,
    p_xform:    Transform3D,
    p_op:       int,
    p_material: StringName,
    p_terrain:  VoxelLodTerrain,
    p_player:   CharacterBody3D,
) -> void:
    shape         = p_shape
    dims          = p_dims
    xform         = p_xform
    op            = p_op
    material_name = p_material
    terrain       = p_terrain
    player        = p_player


func validate() -> bool:
    _ensure_work()
    if _work.is_empty():
        return false
    return not _endangers()


func preview() -> ActionPreview:
    var p := ActionPreview.new()
    _ensure_work()
    for entry in _work:
        if entry[3]:                      # now solid
            p.solid.append(entry[0])
        elif entry[2]:                    # was solid, now air
            p.air.append(entry[0])
    p.refused = _work.is_empty() or _endangers()
    return p


func execute() -> void:
    if terrain == null:
        push_error("CsgAction.execute(): no terrain")
        return
    _ensure_work()

    if op == CsgState.Op.ADD:
        _freeze_bodies_in_volume()

    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    var mat := Materials.from_name(material_name)
    for entry in _work:
        var cell: Vector3i = entry[0]
        vt.set_voxel_f(cell, entry[1])
        if entry[3] and not entry[2]:
            VoxelEventBusSingleton.emit(VoxelAddedEvent.CHANNEL,   VoxelAddedEvent.new(VoxelConstants.GRID_ID, cell, mat))
        elif entry[2] and not entry[3]:
            VoxelEventBusSingleton.emit(VoxelRemovedEvent.CHANNEL, VoxelRemovedEvent.new(VoxelConstants.GRID_ID, cell))

    # Tag the newly-solid voxels with the material id (CHANNEL_INDICES, 8-bit).
    # The DC mesher reads it back and the terrain shader colours by it. Carved
    # cells become air, so they get no material.
    var idx := MaterialPalette.index_of(material_name)
    vt.channel = VoxelBuffer.CHANNEL_INDICES
    for entry in _work:
        if entry[3]:
            vt.set_voxel(entry[0], idx)
    vt.channel = VoxelBuffer.CHANNEL_SDF

    var box := _world_box()
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, box.position, box.size))


# --- Internals ---

# World AABB the stamp touches: the shape's local AABB rotated into world by
# `xform`, grown by MARGIN so the surface band is written all around.
func _world_box() -> AABB:
    return (xform * CsgSdf.local_aabb(shape, dims)).grow(MARGIN)


func _ensure_work() -> void:
    if _work_computed or terrain == null:
        return
    _work          = _compute_work()
    _work_computed = true


func _compute_work() -> Array:
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    var inv  := xform.affine_inverse()
    var box  := _world_box()
    var work: Array = []
    VoxelUtils.for_each_in_bounding_box(
        box.position,
        box.size,
        func(cell: Vector3i) -> void:
            var d := CsgSdf.distance(shape, inv * Vector3(cell), dims)
            d = clampf(d, VoxelConstants.SDF_SOLID, VoxelConstants.SDF_AIR)
            var existing := vt.get_voxel_f(cell)
            var combined := minf(existing, d) if op == CsgState.Op.ADD else maxf(existing, -d)
            if is_equal_approx(combined, existing):
                return
            var was_solid := existing  < VoxelConstants.SDF_SOLID_THRESHOLD
            var now_solid := combined  < VoxelConstants.SDF_SOLID_THRESHOLD
            work.append([cell, combined, was_solid, now_solid])
    )
    return work


# Refuse if the stamp would bury the player (new solid in their capsule) or cut the
# ground out from under their feet (new air in the support box). Boxes: PlayerSafeAction.
func _endangers() -> bool:
    for entry in _work:
        var was_solid: bool = entry[2]
        var now_solid: bool = entry[3]
        if now_solid and not was_solid and buries(entry[0]):
            return true
        if was_solid and not now_solid and drops(entry[0]):
            return true
    return false


# Freeze any RigidBody3D inside the stamp volume before the SDF mutation lands,
# so physics doesn't squirt it sideways from the overlap on the next tick (same
# guard FillAction uses; the buried-body classifier reintegrates it afterwards).
func _freeze_bodies_in_volume() -> void:
    var box   := _world_box()
    var shape3 := BoxShape3D.new()
    shape3.size = box.size
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape              = shape3
    query.transform          = Transform3D(Basis(), box.position + box.size * 0.5)
    query.collide_with_areas = false
    for hit in terrain.get_world_3d().direct_space_state.intersect_shape(query, 32):
        var body := hit.collider as RigidBody3D
        if body != null and not body.freeze:
            body.freeze = true
