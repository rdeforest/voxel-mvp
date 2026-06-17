class_name CsgCylinderShape
extends CsgShape

# Cylinder along local Y. axis 0 = radius, axis 1 = height.

var radius: float
var height: float

func _init(p_radius := 2.0, p_height := 5.0) -> void:
    radius = p_radius
    height = p_height

func mesh() -> Mesh:
    var m := CylinderMesh.new()
    m.top_radius    = radius
    m.bottom_radius = radius
    m.height        = height
    return m

func bounding_extent() -> float:
    return maxf(radius * 2.0, height)

func sdf(local_point: Vector3) -> float:
    return CsgSdf.cylinder(local_point, radius, height)

func local_aabb() -> AABB:
    return AABB(Vector3(-radius, -height * 0.5, -radius), Vector3(radius * 2.0, height, radius * 2.0))

func axis_count() -> int:
    return 2

func axis_label(axis: int) -> String:
    return "height" if axis == 1 else "radius"

func axis_dir(axis: int) -> Vector3:
    return Vector3.UP if axis == 1 else Vector3.RIGHT

func resize_label() -> String:
    return "r %.0f  h %.0f" % [radius, height]

func grow(axis: int, amount: float) -> void:
    if axis == 1:
        height = maxf(MIN_DIM, height + amount)
    else:
        radius = maxf(MIN_DIM, radius + amount)
