class_name VoxelUtils


# Iterate over an axis-aligned bounding box, executing 'operation'.
# `origin` is one corner, `dimensions` is the other. All axes of `origin` must
# be less than or equal to the corresponding axes of `dimensions`, or nothing
# will happen (the incorrect axis will have zero steps and will not iterate).

static func for_each_in_bounding_box(
    origin:         Vector3,
    dimensions:     Vector3,
    operation:      Callable,
) -> void:
    var x_from := int(floor( origin.x                ))
    var y_from := int(floor( origin.y                ))
    var z_from := int(floor( origin.z                ))

    var x_to   := int( ceil( origin.x + dimensions.x ))
    var y_to   := int( ceil( origin.y + dimensions.y ))
    var z_to   := int( ceil( origin.z + dimensions.z ))

    for x         in range(x_from, x_to):
        for y     in range(y_from, y_to):
            for z in range(z_from, z_to):
                var pos := Vector3i(x, y, z)

                operation.call(pos)


static func is_in_sphere(pos: Vector3, center: Vector3, radius: float) -> bool:
    return pos.distance_to(center) <= radius


static func neighbors(pos: Vector3i) -> Array[Vector3i]:
    return [
        pos + Vector3i( 1,  0,  0),
        pos + Vector3i(-1,  0,  0),
        pos + Vector3i( 0,  1,  0),
        pos + Vector3i( 0, -1,  0),
        pos + Vector3i( 0,  0,  1),
        pos + Vector3i( 0,  0, -1),
    ]


# Returns the voxel cells an AABB occupies.
# Thin dimensions (< VOXEL_SIZE) collapse to one cell containing the center,
# preventing a board 0.012 m thick from straddling two 1 m voxel boundaries.
static func footprint_from_aabb(aabb: AABB) -> Array[Vector3i]:
    if aabb.size == Vector3.ZERO:
        return []
    var cell_aabb := _aabb_to_cell_aabb(aabb)
    var result:   Array[Vector3i] = []
    for_each_in_bounding_box(
        cell_aabb.position,
        cell_aabb.size,
        func(pos: Vector3i) -> void: result.append(pos)
    )
    return result


# One axis of the cell-snapped AABB: a span >= one voxel snaps out to the enclosing whole
# cells; a sub-voxel span collapses to the single cell holding its midpoint. [origin, size].
static func _cell_axis(position: float, size: float) -> Array:
    if size >= VoxelConstants.VOXEL_SIZE:
        var origin: float = floor(position)
        return [origin, ceil(position + size) - origin]
    return [floor(position + size * 0.5), 1.0]


static func _aabb_to_cell_aabb(aabb: AABB) -> AABB:
    var x := _cell_axis(aabb.position.x, aabb.size.x)
    var y := _cell_axis(aabb.position.y, aabb.size.y)
    var z := _cell_axis(aabb.position.z, aabb.size.z)
    return AABB(Vector3(x[0], y[0], z[0]), Vector3(x[1], y[1], z[1]))
