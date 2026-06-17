class_name CsgBoxShape
extends CsgShape

var size: Vector3

func _init(p_size := Vector3(4.0, 4.0, 4.0)) -> void:
    size = p_size

func mesh() -> Mesh:
    var m := BoxMesh.new()
    m.size = size
    return m

func bounding_extent() -> float:
    return maxf(size.x, maxf(size.y, size.z))

func sdf(local_point: Vector3) -> float:
    return CsgSdf.box(local_point, size)

func local_aabb() -> AABB:
    return AABB(-size * 0.5, size)

func axis_count() -> int:
    return 3

func axis_label(axis: int) -> String:
    return ["X", "Y", "Z"][axis]

func axis_dir(axis: int) -> Vector3:
    return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis]

func resize_label() -> String:
    return "X×Y×Z %.0f×%.0f×%.0f" % [size.x, size.y, size.z]

func grow(axis: int, amount: float) -> void:
    size[axis] = maxf(MIN_DIM, size[axis] + amount)
