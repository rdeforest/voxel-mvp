extends GutTest

# The CSG primitives are only useful as a mesh ground-truth if their analytic SDF
# is correct: negative inside, positive outside, ~0 on the surface, and (for the
# exact box/sphere) the right magnitude. These tests pin that, plus the rotation
# round-trip the action relies on (evaluate in the inverse-transformed frame).

const EPS := 1e-4


func test_sphere_sign_and_distance() -> void:
    assert_almost_eq(CsgSdf.sphere(Vector3.ZERO,            2.0), -2.0, EPS, "centre is 2 inside")
    assert_almost_eq(CsgSdf.sphere(Vector3(2, 0, 0),        2.0),  0.0, EPS, "surface is zero")
    assert_almost_eq(CsgSdf.sphere(Vector3(5, 0, 0),        2.0),  3.0, EPS, "outside is +3")


func test_box_sign_and_distance() -> void:
    var size := Vector3(4, 4, 4)   # half-extent 2
    assert_almost_eq(CsgSdf.box(Vector3.ZERO,        size), -2.0, EPS, "centre is 2 from nearest face")
    assert_almost_eq(CsgSdf.box(Vector3(2, 0, 0),    size),  0.0, EPS, "face is zero")
    assert_almost_eq(CsgSdf.box(Vector3(5, 0, 0),    size),  3.0, EPS, "3 past the +X face")
    # Corner distance is the diagonal beyond the box, not an axis distance.
    assert_almost_eq(CsgSdf.box(Vector3(5, 5, 0),    size),  sqrt(18.0), EPS, "corner is diagonal")


func test_cylinder_sign() -> void:
    # radius 3 about Y, height 4 (|y| <= 2).
    assert_lt(CsgSdf.cylinder(Vector3.ZERO,       3.0, 4.0), 0.0, "centre inside")
    assert_almost_eq(CsgSdf.cylinder(Vector3(3, 0, 0),  3.0, 4.0), 0.0, EPS, "radial surface zero")
    assert_almost_eq(CsgSdf.cylinder(Vector3(0, 2, 0),  3.0, 4.0), 0.0, EPS, "cap surface zero")
    assert_gt(CsgSdf.cylinder(Vector3(0, 5, 0),  3.0, 4.0), 0.0, "above the cap is outside")


func test_rotation_roundtrip_is_distance_preserving() -> void:
    # A point on the +X face of a rotated box, evaluated in the inverse frame, is
    # still on the surface (the action's exact mechanism).
    var size  := Vector3(4, 4, 4)
    var basis := Basis(Vector3.UP, deg_to_rad(37.0)) * Basis(Vector3.RIGHT, deg_to_rad(20.0))
    var origin := Vector3(10, -3, 5)
    var xform := Transform3D(basis, origin)
    var surface_local := Vector3(2, 0, 0)               # on the +X face
    var surface_world := xform * surface_local
    var d := CsgSdf.box(xform.affine_inverse() * surface_world, size)
    assert_almost_eq(d, 0.0, EPS, "rotated surface point still reads as on-surface")
