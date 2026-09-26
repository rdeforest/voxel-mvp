class_name VoxelUtils


# Visit every CELL whose unit box overlaps the half-open box [origin, origin + dimensions),
# executing `operation(cell)`. `dimensions` is an extent (a size), not the far corner; a
# non-positive axis visits nothing. This walks cells, not sample points: pair it with a
# membership test at `sample_point(cell)` (see cells_in_sphere), never at `Vector3(cell)`.

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


static func euler_basis(degrees: Vector3) -> Basis:
    var b := Basis.IDENTITY

    b = b.rotated(Vector3.RIGHT,   deg_to_rad(degrees.x))
    b = b.rotated(Vector3.UP,      deg_to_rad(degrees.y))
    b = b.rotated(Vector3.FORWARD, deg_to_rad(degrees.z))

    return b


static func is_in_sphere(pos: Vector3, center: Vector3, radius: float) -> bool:
    return pos.distance_to(center) <= radius


# The ONE cell -> sample-point mapping: a cell is represented by its centre. Everything that
# asks "is this cell solid / what material is it / is it in this volume" samples here, so every
# subsystem classifies a boundary cell the same way (docs/CODE-MAP.md §SDF conventions).
# Vector3(cell) is the cell's minimum CORNER — a store lattice point, not the cell.
static func sample_point(cell: Vector3i) -> Vector3:
    return Vector3(cell) + VoxelConstants.VOXEL_CENTER_OFFSET


# Every cell whose sample point lies in the CLOSED ball. The walk box is derived from the
# ball, and a sample point on the far (+) boundary sits half a cell inside the box's last
# cell, so the inclusive test and the half-open cell walk agree on both sides.
static func cells_in_sphere(center: Vector3, radius: float) -> Array[Vector3i]:
    var out: Array[Vector3i] = []
    for_each_in_bounding_box(
        center - Vector3.ONE *  radius,
                 Vector3.ONE * (radius * 2.0),
        func(cell: Vector3i) -> void:
            if is_in_sphere(sample_point(cell), center, radius):
                out.append(cell)
    )
    return out


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
    var result: Array[Vector3i] = []

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
