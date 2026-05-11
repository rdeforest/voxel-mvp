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

