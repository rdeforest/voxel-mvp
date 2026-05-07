class_name VoxelUtils

static func for_each_in_sphere(
    center: Vector3,
    radius: float,
    callback: Callable,
) -> void:
    var radius_int := int(radius) + 1
    var center_i := Vector3i(
        roundi(center.x),
        roundi(center.y),
        roundi(center.z)
    )
    for x in range(-radius_int, radius_int + 1):
        for y in range(-radius_int, radius_int + 1):
            for z in range(-radius_int, radius_int + 1):
                var pos := center_i + Vector3i(x, y, z)
                if Vector3(pos).distance_to(center) <= radius:
                    callback.call(pos)