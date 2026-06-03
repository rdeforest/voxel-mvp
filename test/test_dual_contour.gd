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


# Bite C: the QEF must recover sharp creases, not round them off. A box has flat
# faces, 90° edges, and 3-plane corners. Edges are placed off-grid (half-extent
# 5.3) so the mesher has to reconstruct the crease inside cells. An averaging
# mesher (surface nets) would pull edge/corner vertices inward; the QEF keeps
# faces flat at the bound and corners out at the full extent.
class TestDualContourSharpBox:
    extends GutTest

    const B := 5.3

    var _verts: PackedVector3Array

    func before_all() -> void:
        var sdf := func(p: Vector3) -> float: return SdfShapes.box(p, Vector3.ONE * B)
        var mesh := DualContour.build_mesh(sdf, Vector3i(20, 20, 20), Vector3.ONE * -10.0, 1.0)
        _verts = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

    func test_corners_reach_full_extent():
        var max_coord := 0.0
        for v in _verts:
            max_coord = maxf(max_coord, maxf(absf(v.x), maxf(absf(v.y), absf(v.z))))
        assert_almost_eq(max_coord, B, 0.15)   # not rounded inward

    func test_plus_x_face_is_flat_at_the_bound():
        var max_dev := 0.0
        var n := 0
        for v in _verts:
            if v.x > 4.5:                       # vertices on/near the +X face
                max_dev = maxf(max_dev, absf(v.x - B))
                n += 1
        assert_gt(n, 5)                         # actually found face vertices
        assert_lt(max_dev, 0.15)               # they sit on the plane, edges included

    func test_wedge_meshes_without_error():
        var sdf := func(p: Vector3) -> float: return SdfShapes.wedge(p, Vector3.ONE * 5.0)
        var mesh := DualContour.build_mesh(sdf, Vector3i(20, 20, 20), Vector3.ONE * -10.0, 1.0)
        assert_eq(mesh.get_surface_count(), 1)
        assert_gt((mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 50)
