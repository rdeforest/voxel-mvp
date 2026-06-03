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


# Bite B: ill-conditioned QEF inputs. A flat region gives a rank-1 AᵀA (two zero
# eigenvalues); a straight crease gives rank-2; near-parallel planes give tiny
# eigenvalues a naive pseudo-inverse would divide by, flinging the vertex out or
# producing NaN. The eigenvalue clamp + mass-point bias + cell clamp must keep
# every result finite and inside the cell, and sensible (on the plane/crease).
class TestQefRobustness:
    extends GutTest

    const LO := Vector3.ZERO
    const HI := Vector3.ONE     # unit cell [0,1]^3

    func _assert_sane(x: Vector3) -> void:
        assert_true(is_finite(x.x) and is_finite(x.y) and is_finite(x.z), "finite")
        assert_between(x.x, LO.x, HI.x)
        assert_between(x.y, LO.y, HI.y)
        assert_between(x.z, LO.z, HI.z)

    func test_flat_region_is_finite_and_on_the_plane():
        # Coplanar crossings, all normals +Y -> rank-1 system, tangent
        # position underdetermined. Must not divide by the two zero eigenvalues.
        var q := QefSolver.new()
        q.add_plane(Vector3(0.2, 0.5, 0.3), Vector3(0, 1, 0))
        q.add_plane(Vector3(0.8, 0.5, 0.1), Vector3(0, 1, 0))
        q.add_plane(Vector3(0.4, 0.5, 0.9), Vector3(0, 1, 0))
        var x := q.solve(LO, HI)
        _assert_sane(x)
        assert_almost_eq(x.y, 0.5, 0.0001)

    func test_straight_crease_rank2_lands_on_the_edge_line():
        # +X and +Y faces meeting at the line x=0.7, y=0.3 (edge along z).
        # Position along z underdetermined.
        var q := QefSolver.new()
        q.add_plane(Vector3(0.7, 0.1, 0.2), Vector3(1, 0, 0))
        q.add_plane(Vector3(0.7, 0.9, 0.8), Vector3(1, 0, 0))
        q.add_plane(Vector3(0.1, 0.3, 0.4), Vector3(0, 1, 0))
        q.add_plane(Vector3(0.9, 0.3, 0.6), Vector3(0, 1, 0))
        var x := q.solve(LO, HI)
        _assert_sane(x)
        assert_almost_eq(x.x, 0.7, 0.001)
        assert_almost_eq(x.y, 0.3, 0.001)

    func test_near_parallel_normals_do_not_blow_up():
        # Almost-coplanar planes with tiny tilts and slight inconsistency: the
        # weak directions have ~1e-8 eigenvalues. Without the clamp the offset
        # along them explodes; with it the vertex stays sane.
        var q := QefSolver.new()
        q.add_plane(Vector3(0.1, 0.50, 0.2), Vector3(0.0002, 1, 0).normalized())
        q.add_plane(Vector3(0.9, 0.52, 0.8), Vector3(0, 1, 0.0002).normalized())
        q.add_plane(Vector3(0.5, 0.48, 0.5), Vector3(-0.0002, 1, 0).normalized())
        _assert_sane(q.solve(LO, HI))

    func test_contradictory_far_planes_clamp_into_cell():
        var q := QefSolver.new()
        q.add_plane(Vector3(10, 0, 0), Vector3(1, 0, 0))
        q.add_plane(Vector3(0, 10, 0), Vector3(0, 1, 0))
        q.add_plane(Vector3(0, 0, 10), Vector3(0, 0, 1))
        _assert_sane(q.solve(LO, HI))

    func test_perturbed_flat_sweep_always_stays_in_cell():
        # Deterministic perturbations (no RNG): many near-flat regions, every
        # solve finite and in-cell.
        for i in 60:
            var j := float(i % 9 - 4) * 0.0004
            var q := QefSolver.new()
            q.add_plane(Vector3(0.1, 0.5, 0.2), Vector3(j, 1, 0).normalized())
            q.add_plane(Vector3(0.9, 0.5, 0.8), Vector3(0, 1, j).normalized())
            q.add_plane(Vector3(0.5, 0.5, 0.5), Vector3(-j, 1, j).normalized())
            _assert_sane(q.solve(LO, HI))


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
            var centroid := (a + b + c) / 3.0   # ~outward direction from the origin
            # Godot front faces are clockwise-from-front, so a correctly-wound
            # outward face's right-hand normal points inward (dot outward < 0).
            if face_n.dot(centroid) < 0.0:
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
    var _idx: PackedInt32Array

    func before_all() -> void:
        var sdf := func(p: Vector3) -> float: return SdfShapes.box(p, Vector3.ONE * B)
        var mesh := DualContour.build_mesh(sdf, Vector3i(20, 20, 20), Vector3.ONE * -10.0, 1.0)
        var arrays := mesh.surface_get_arrays(0)
        _verts = arrays[Mesh.ARRAY_VERTEX]
        _idx   = arrays[Mesh.ARRAY_INDEX]

    func test_faces_point_outward():
        var good := 0
        var total := _idx.size() / 3
        for i in range(0, _idx.size(), 3):
            var a := _verts[_idx[i]]
            var b := _verts[_idx[i + 1]]
            var c := _verts[_idx[i + 2]]
            var face_n := (b - a).cross(c - a)
            var centroid := (a + b + c) / 3.0   # ~outward direction from the origin
            # Godot front faces are CW-from-front: outward face's right-hand
            # normal points inward, so the dot with outward is negative.
            if face_n.dot(centroid) < 0.0:
                good += 1
        assert_gt(float(good) / float(total), 0.95)

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

    func test_on_grid_box_still_winds_outward():
        # Faces land exactly on integer grid planes (the case that degenerated in
        # the preview); the surface nudge must keep winding consistent.
        var sdf := func(p: Vector3) -> float: return SdfShapes.box(p, Vector3.ONE * 6.0)
        var mesh := DualContour.build_mesh(sdf, Vector3i(20, 20, 20), Vector3.ONE * -10.0, 1.0)
        var arrays := mesh.surface_get_arrays(0)
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var idx: PackedInt32Array     = arrays[Mesh.ARRAY_INDEX]
        var good := 0
        var total := idx.size() / 3
        for i in range(0, idx.size(), 3):
            var a := verts[idx[i]]
            var b := verts[idx[i + 1]]
            var c := verts[idx[i + 2]]
            if (b - a).cross(c - a).dot((a + b + c) / 3.0) < 0.0:   # Godot CW-from-front
                good += 1
        assert_gt(float(good) / float(total), 0.95)

    func test_wedge_meshes_without_error():
        var sdf := func(p: Vector3) -> float: return SdfShapes.wedge(p, Vector3.ONE * 5.0)
        var mesh := DualContour.build_mesh(sdf, Vector3i(20, 20, 20), Vector3.ONE * -10.0, 1.0)
        assert_eq(mesh.get_surface_count(), 1)
        assert_gt((mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 50)
