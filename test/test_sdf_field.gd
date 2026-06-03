extends GutTest

# Pluggable field source: SdfAnalytic (callable) vs SdfBaked (pre-sampled grid).
# Baked must match analytic at lattice samples, and both must mesh the same shape
# (the A/B comparison harness the field split is for).

const R      := 8.0
const ORIGIN := Vector3(-12, -12, -12)
const RES    := Vector3i(24, 24, 24)

var _fn := func(p: Vector3) -> float: return p.length() - R


func _baked() -> SdfBaked:
    return SdfBaked.bake(SdfAnalytic.new(_fn), ORIGIN, 1.0, RES + Vector3i.ONE)

func test_baked_matches_analytic_at_lattice():
    var analytic := SdfAnalytic.new(_fn)
    var baked := _baked()
    for c in [Vector3i(0, 0, 0), Vector3i(12, 12, 12), Vector3i(24, 24, 24), Vector3i(5, 18, 3)]:
        var world := ORIGIN + Vector3(c)
        assert_almost_eq(baked.value(world), analytic.value(world), 0.0001)

func test_baked_gradient_points_outward():
    # On the +X side of the sphere the stored-data gradient still points ~+X.
    var g := _baked().gradient(Vector3(R, 0, 0))
    assert_gt(g.dot(Vector3.RIGHT), 0.8)

func _assert_sphere(mesh: ArrayMesh) -> void:
    assert_eq(mesh.get_surface_count(), 1)
    var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    assert_gt(verts.size(), 100)
    var max_dev := 0.0
    for v in verts:
        max_dev = maxf(max_dev, absf(v.length() - R))
    assert_lt(max_dev, 1.5)

func test_analytic_and_baked_mesh_the_same_sphere():
    _assert_sphere(DualContour.build_field(SdfAnalytic.new(_fn), RES, ORIGIN, 1.0))
    _assert_sphere(DualContour.build_field(_baked(), RES, ORIGIN, 1.0))
