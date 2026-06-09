extends GutTest

# CsgState: per-shape dims, the resize wheel / axis cycle, and the bounding extent
# that drives the air-preview distance. Plus the EditMode air flags the CSG tool
# relies on (inert on air, custom distance).

func test_bounding_extent_per_shape() -> void:
    var cs := CsgState.new()
    cs.set_shape(CsgSdf.Shape.BOX)
    (cs.active_shape() as CsgBoxShape).size = Vector3(2, 9, 4)
    assert_eq(cs.bounding_extent(), 9.0, "box -> largest side")
    cs.set_shape(CsgSdf.Shape.CYLINDER)
    var cyl := cs.active_shape() as CsgCylinderShape
    cyl.radius = 5.0   # diameter 10
    cyl.height = 3.0
    assert_eq(cs.bounding_extent(), 10.0, "cylinder -> max(diameter, height)")
    cs.set_shape(CsgSdf.Shape.SPHERE)
    (cs.active_shape() as CsgSphereShape).radius = 6.0
    assert_eq(cs.bounding_extent(), 12.0, "sphere -> diameter")


func test_wheel_grows_active_axis_only() -> void:
    var cs := CsgState.new()
    cs.set_shape(CsgSdf.Shape.BOX)
    var box := cs.active_shape() as CsgBoxShape
    box.size = Vector3(4, 4, 4)
    cs.active_axis = 1            # Y
    cs.grow(2.0)                  # +2 * RESIZE_STEP
    assert_eq(box.size, Vector3(4, 6, 4), "only the active axis grows")


func test_grow_clamps_to_min() -> void:
    var cs := CsgState.new()
    cs.set_shape(CsgSdf.Shape.SPHERE)
    var sphere := cs.active_shape() as CsgSphereShape
    sphere.radius = 1.0
    cs.grow(-100.0)
    assert_eq(sphere.radius, CsgState.MIN_DIM, "can't shrink below MIN_DIM")


func test_cylinder_axis_maps_radius_or_height() -> void:
    var cs := CsgState.new()
    cs.set_shape(CsgSdf.Shape.CYLINDER)
    assert_eq(cs.axis_dir(), Vector3.RIGHT, "radius axis points sideways")
    cs.active_axis = 1
    assert_eq(cs.axis_dir(), Vector3.UP, "height axis points up")


func test_sphere_has_no_axis_arrow() -> void:
    var cs := CsgState.new()
    cs.set_shape(CsgSdf.Shape.SPHERE)
    assert_eq(cs.axis_dir(), Vector3.ZERO, "uniform shape -> no arrow")


func test_edit_mode_air_flags() -> void:
    var inert := EditMode.new().air_placement(true).act_on_air(false).air_distance(func(): return 9.0)
    assert_true(inert.allows_air_placement, "shows a ghost on air")
    assert_false(inert.acts_on_air, "but won't act on air")
    assert_eq(inert.get_air_distance.call(), 9.0)
    assert_true(EditMode.new().acts_on_air, "acts_on_air defaults true (Build)")
