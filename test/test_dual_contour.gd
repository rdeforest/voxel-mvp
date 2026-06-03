extends GutTest

# Bite A coverage: the QEF solver on well/ill-conditioned inputs, and the
# uniform-grid Dual Contouring mesher on an analytic sphere.

class TestQefSolver:
    extends GutTest

    var _wide_min := Vector3(-100, -100, -100)
    var _wide_max := Vector3(100, 100, 100)

    func test_three_orthogonal_planes_meet_at_a_point():
        var q := QefSolver.new()
        q.add_plane(Vector3(2, 0, 0), Vector3(1, 0, 0))
        q.add_plane(Vector3(0, 3, 0), Vector3(0, 1, 0))
        q.add_plane(Vector3(0, 0, 4), Vector3(0, 0, 1))
        assert_almost_eq(q.solve(_wide_min, _wide_max), Vector3(2, 3, 4), Vector3.ONE * 0.001)

    func test_single_plane_solution_lies_on_the_plane():
        var q := QefSolver.new()
        q.add_plane(Vector3(0, 5, 0), Vector3(0, 1, 0))
        assert_almost_eq(q.solve(_wide_min, _wide_max).y, 5.0, 0.001)

    func test_parallel_planes_average_their_offset():
        var q := QefSolver.new()
        q.add_plane(Vector3(0, 4, 0), Vector3(0, 1, 0))
        q.add_plane(Vector3(0, 6, 0), Vector3(0, 1, 0))
        assert_almost_eq(q.solve(_wide_min, _wide_max).y, 5.0, 0.001)

    func test_result_is_clamped_into_the_cell():
        var q := QefSolver.new()
        q.add_plane(Vector3(50, 0, 0), Vector3(1, 0, 0))
        var x := q.solve(Vector3.ZERO, Vector3.ONE)
        assert_between(x.x, 0.0, 1.0)

    func test_no_planes_returns_cell_centre():
        var q := QefSolver.new()
        assert_almost_eq(q.solve(Vector3.ZERO, Vector3.ONE), Vector3.ONE * 0.5, Vector3.ONE * 0.0001)


class TestDualContourSphere:
    extends GutTest

    const R := 8.0

    var _sdf := func(p: Vector3) -> float: return p.length() - R
    var _mesh: ArrayMesh
    var _verts: PackedVector3Array
    var _idx: PackedInt32Array

    func before_all() -> void:
        _mesh  = DualContour.build_mesh(_sdf, Vector3i(24, 24, 24), Vector3(-12, -12, -12), 1.0)
        var arrays := _mesh.surface_get_arrays(0)
        _verts = arrays[Mesh.ARRAY_VERTEX]
        _idx   = arrays[Mesh.ARRAY_INDEX]

    func test_produces_a_surface():
        assert_eq(_mesh.get_surface_count(), 1)
        assert_gt(_verts.size(), 100)
        assert_eq(_idx.size() % 3, 0)

    func test_vertices_hug_the_sphere():
        var max_dev := 0.0
        for v in _verts:
            max_dev = maxf(max_dev, absf(v.length() - R))
        assert_lt(max_dev, 1.5)   # within ~one cell of the true surface

    func test_faces_point_outward():
        var good := 0
        var total := _idx.size() / 3
        for i in range(0, _idx.size(), 3):
            var a := _verts[_idx[i]]
            var b := _verts[_idx[i + 1]]
            var c := _verts[_idx[i + 2]]
            var face_n := (b - a).cross(c - a)
            var centroid := (a + b + c) / 3.0   # from sphere centre at origin
            if face_n.dot(centroid) > 0.0:
                good += 1
        assert_gt(float(good) / float(total), 0.95)
