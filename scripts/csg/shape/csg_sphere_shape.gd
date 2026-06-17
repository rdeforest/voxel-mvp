class_name CsgSphereShape
extends CsgShape

# Uniform — a single resizable radius, so it has no resize-axis arrow.

var radius: float

func _init(p_radius := 3.0) -> void:
    radius = p_radius

func mesh() -> Mesh:
    var m := SphereMesh.new()
    m.radius = radius
    m.height = radius * 2.0
    return m

func bounding_extent() -> float:
    return radius * 2.0

func sdf(local_point: Vector3) -> float:
    return CsgSdf.sphere(local_point, radius)

func local_aabb() -> AABB:
    return AABB(-Vector3.ONE * radius, Vector3.ONE * radius * 2.0)

func axis_label(_axis: int) -> String:
    return "radius"

func resize_label() -> String:
    return "r %.0f" % radius

func grow(_axis: int, amount: float) -> void:
    radius = maxf(MIN_DIM, radius + amount)
