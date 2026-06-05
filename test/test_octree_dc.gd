extends GutTest

# Bite D: adaptive-octree Dual Contouring.
#   - a uniform-depth surface octree reproduces a watertight sphere (the
#     minimal-edge meshing machinery is correct).
#   - forcing a level transition through the sphere (depth 5 one side, 4 the
#     other) still yields a watertight surface (the seam is crack-free).
#
# Watertight = a closed 2-manifold: every edge shared by exactly two triangles
# (no boundary edges, no non-manifold edges). That single invariant catches both
# holes and cracks across the level transition.

const CENTER := Vector3(16, 16, 16)
const RADIUS := 10.0
const DEPTH  := 5                       # root cube is [0, 32]^3

var _sdf := func(p: Vector3) -> float: return p.distance_to(CENTER) - RADIUS


func _edge_audit(idx: PackedInt32Array) -> Dictionary:
    var counts := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
            var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[key] = counts.get(key, 0) + 1
    var boundary := 0
    var nonmanifold := 0
    for k in counts:
        if counts[k] == 1:   boundary += 1
        elif counts[k] > 2:  nonmanifold += 1
    return {"boundary": boundary, "nonmanifold": nonmanifold}

func _arrays(mesh: ArrayMesh) -> Array:
    assert_eq(mesh.get_surface_count(), 1, "produced a surface")
    return mesh.surface_get_arrays(0)

func _assert_watertight(verts: PackedVector3Array, idx: PackedInt32Array) -> void:
    assert_gt(verts.size(), 200)
    assert_eq(idx.size() % 3, 0)
    var audit := _edge_audit(idx)
    assert_eq(audit["boundary"], 0, "boundary edges (holes/cracks)")
    assert_eq(audit["nonmanifold"], 0, "non-manifold edges")

func _assert_hugs(verts: PackedVector3Array, tol: float) -> void:
    var max_dev := 0.0
    for v in verts:
        max_dev = maxf(max_dev, absf(v.distance_to(CENTER) - RADIUS))
    assert_lt(max_dev, tol)

func _assert_faces_outward(verts: PackedVector3Array, idx: PackedInt32Array) -> void:
    var good := 0
    @warning_ignore("integer_division")
    var total := idx.size() / 3
    for i in range(0, idx.size(), 3):
        var a := verts[idx[i]]
        var b := verts[idx[i + 1]]
        var c := verts[idx[i + 2]]
        var outward := (a + b + c) / 3.0 - CENTER
        # Godot CW-from-front: a correctly-wound outward face's right-hand normal
        # points inward, so dot with the outward direction is negative.
        if (b - a).cross(c - a).dot(outward) < 0.0:
            good += 1
    assert_gt(float(good) / float(total), 0.95)


func test_uniform_depth_sphere_is_watertight():
    var arrays := _arrays(OctreeDC.build_mesh(_sdf, DEPTH))
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array     = arrays[Mesh.ARRAY_INDEX]
    _assert_watertight(verts, idx)
    _assert_hugs(verts, 1.5)
    _assert_faces_outward(verts, idx)

func test_level_transition_is_watertight():
    # depth 5 where x < 16, depth 4 where x >= 16 -> a 1-level seam down the middle.
    var refine := func(center: Vector3, _size: float, depth: int) -> bool:
        return depth < (5 if center.x < 16.0 else 4)
    var arrays := _arrays(OctreeDC.build_mesh(_sdf, DEPTH, refine))
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array     = arrays[Mesh.ARRAY_INDEX]
    _assert_watertight(verts, idx)
    _assert_hugs(verts, 2.5)            # coarse side cells are size 2
    _assert_faces_outward(verts, idx)

# An abrupt >1-level transition still meshes crack-free WITHOUT any octree-balance
# pass, because the minimal-edge meshing finds the cells around each edge by
# point-location and fans fine sub-edges to the coarse cell's single vertex for any
# level difference. This guards that property: a nearly-flat sloped sheet (flat ->
# coarse cells never undersample, so the only legit boundary edges are the rim
# where the sheet meets the side walls) with an abrupt size-8 core in fine size-1
# surroundings (a 3-level jump). Fine wall cells keep rim vertices within ~1 unit
# of a wall, so any boundary edge further in is a crack. Zero interior boundary
# edges == crack-free.
const SHEET_DEPTH := 5                  # root [0, 32]^3
const SHEET_MAX   := 32.0
const SHEET_MID   := 16.0
const WALL_EPS    := 2.0                 # > finest wall cell (size 1); rim vertices sit within this of a wall

func _sheet_sdf(p: Vector3) -> float:
    return p.y - (SHEET_MID + 0.05 * p.x)   # ~flat, off-grid; exits only on the four side walls

func _on_side_wall(v: Vector3) -> bool:
    return absf(v.x) < WALL_EPS or absf(v.x - SHEET_MAX) < WALL_EPS \
        or absf(v.z) < WALL_EPS or absf(v.z - SHEET_MAX) < WALL_EPS

func _interior_boundary_edges(verts: PackedVector3Array, idx: PackedInt32Array) -> int:
    var counts := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
            var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[key] = counts.get(key, 0) + 1
    var interior := 0
    for k in counts:
        if counts[k] == 1 and not (_on_side_wall(verts[k.x]) and _on_side_wall(verts[k.y])):
            interior += 1
    return interior

func test_abrupt_level_jump_has_no_interior_cracks():
    var sheet := func(p: Vector3) -> float: return _sheet_sdf(p)
    var mid := Vector2(SHEET_MID, SHEET_MID)
    # An ABRUPT coarse disk (size 8) in the centre, fine (size 1) everywhere else
    # incl. the walls. The size-8/size-1 adjacency at the disk rim is a 3-level
    # jump -- the point-location fan must stitch it without interior cracks.
    var refine := func(center: Vector3, size: float, _depth: int) -> bool:
        var target := 8.0 if Vector2(center.x, center.z).distance_to(mid) < 8.0 else 1.0
        return size > target
    var arrays := _arrays(OctreeDC.build_mesh(sheet, SHEET_DEPTH, refine))
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array     = arrays[Mesh.ARRAY_INDEX]
    assert_gt(idx.size() / 3, 50, "meaningfully tessellated")
    assert_eq(_edge_audit(idx)["nonmanifold"], 0, "non-manifold edges")
    assert_eq(_interior_boundary_edges(verts, idx), 0, "interior boundary edges (cracks)")
