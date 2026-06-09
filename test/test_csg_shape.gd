extends GutTest

# CsgShape strategies: each primitive owns its bounds, local AABB, resize axes, and
# SDF (wrapping CsgSdf). These pin the per-shape behaviour CsgState delegates to —
# the local-AABB assertions that used to live in test_csg_sdf moved here.

const EPS := 1e-4


func test_box_bounds_axes_and_sdf() -> void:
    var box := CsgBoxShape.new(Vector3(4, 6, 2))
    assert_eq(box.local_aabb(), AABB(Vector3(-2, -3, -1), Vector3(4, 6, 2)), "AABB is the centred full size")
    assert_eq(box.bounding_extent(), 6.0, "largest side")
    assert_eq(box.axis_count(), 3, "three independent extents")
    assert_eq(box.axis_dir(1), Vector3.UP, "Y axis points up")
    assert_almost_eq(box.sdf(Vector3.ZERO), -1.0, EPS, "centre is the nearest-face distance (smallest half-extent)")
    box.grow(0, 10.0)
    assert_eq(box.size.x, 14.0, "grow adds to the chosen axis only")


func test_cylinder_bounds_axes_and_sdf() -> void:
    var cyl := CsgCylinderShape.new(2.0, 8.0)
    assert_eq(cyl.local_aabb(), AABB(Vector3(-2, -4, -2), Vector3(4, 8, 4)), "r2 h8")
    assert_eq(cyl.bounding_extent(), 8.0, "max(diameter, height)")
    assert_eq(cyl.axis_count(), 2, "radius + height")
    assert_eq(cyl.axis_dir(1), Vector3.UP, "height axis points up")
    assert_eq(cyl.axis_dir(0), Vector3.RIGHT, "radius axis points sideways")
    assert_almost_eq(cyl.sdf(Vector3(2, 0, 0)), 0.0, EPS, "radial surface is zero")


func test_sphere_bounds_axes_and_sdf() -> void:
    var sphere := CsgSphereShape.new(3.0)
    assert_eq(sphere.local_aabb(), AABB(-Vector3.ONE * 3.0, Vector3.ONE * 6.0), "centred diameter box")
    assert_eq(sphere.bounding_extent(), 6.0, "diameter")
    assert_eq(sphere.axis_count(), 1, "uniform — one radius")
    assert_eq(sphere.axis_dir(0), Vector3.ZERO, "no resize arrow")
    assert_almost_eq(sphere.sdf(Vector3(3, 0, 0)), 0.0, EPS, "surface is zero")


func test_grow_clamps_to_min() -> void:
    var sphere := CsgSphereShape.new(1.0)
    sphere.grow(0, -100.0)
    assert_eq(sphere.radius, CsgShape.MIN_DIM, "can't shrink below MIN_DIM")
