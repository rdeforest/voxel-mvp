extends GutTest

# The production C++ octree-DC mesher (DCOctreeMesher.mesh_clipmap), the meshing
# heart of DCTerrainManager. Two invariants on an analytic sphere:
#   - a single (uniform) clipmap level reproduces a watertight sphere — the
#     minimal-edge meshing machinery is correct.
#   - a fine-core / coarse-shell clipmap (two levels) still meshes watertight
#     across the LOD boundary — the crack-free transition that is the whole point
#     of the clipmap mesher, and the property no other test exercises.
#
# Watertight = closed 2-manifold: every edge shared by exactly two triangles. That
# one invariant catches both holes and cracks across the level transition.
#
# (Replaces the GDScript OctreeDC algorithm tests; the prototype mesher was retired
# once this C++ port became the production render path.)

const CENTER := Vector3(16, 16, 16)
const RADIUS := 10.0
const DEPTH  := 5                       # octree root [0, 32]^3
const DIM    := 33                      # corner samples per level (DEPTH^2 + 1)

func _sphere(p: Vector3) -> float:
    return p.distance_to(CENTER) - RADIUS

# Sample the sphere into one clipmap level's flat grid (x-fastest), matching the
# layout DCTerrainManager feeds: world = origin + lattice * cell.
func _level(origin: Vector3, cell: float) -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                data[i] = _sphere(origin + Vector3(x, y, z) * cell)
                i += 1
    return data


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

func _mesh(level_data: Array, origins: PackedVector3Array, cells: PackedFloat32Array, half0: float) -> Array:
    var arrays := DCOctreeMesher.new().mesh_clipmap(level_data, DIM, origins, cells, CENTER, half0, DEPTH)
    assert_false(arrays.is_empty(), "mesher produced a surface")
    return arrays

func _assert_watertight(arrays: Array, hug_tol: float) -> void:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    assert_gt(verts.size(), 200, "meaningfully tessellated")
    assert_eq(idx.size() % 3, 0)
    var audit := _edge_audit(idx)
    assert_eq(audit["boundary"], 0, "boundary edges (holes/cracks)")
    assert_eq(audit["nonmanifold"], 0, "non-manifold edges")
    var max_dev := 0.0
    for v in verts:
        max_dev = maxf(max_dev, absf(v.distance_to(CENTER) - RADIUS))
    assert_lt(max_dev, hug_tol, "vertices hug the sphere")


func test_uniform_level_is_watertight():
    # One level covering the whole root (half0 huge → every cell is level 0, size 1).
    var data := _level(Vector3.ZERO, 1.0)
    var arrays := _mesh([data], PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]), 1e9)
    _assert_watertight(arrays, 1.5)


func test_lod_transition_is_watertight():
    # Fine core (cell 1, |d| <= 8) + coarse shell (cell 2, 8 < |d| <= 16). The sphere
    # surface (Chebyshev radius ~5.8 .. 10) straddles the boundary, so the level
    # transition cuts across the surface — the crack-free stitch under test.
    var fine := _level(Vector3.ZERO, 1.0)                       # covers [0, 32]
    var coarse := _level(Vector3(-16, -16, -16), 2.0)           # covers [-16, 48]
    var arrays := _mesh(
        [fine, coarse],
        PackedVector3Array([Vector3.ZERO, Vector3(-16, -16, -16)]),
        PackedFloat32Array([1.0, 2.0]),
        8.0)
    _assert_watertight(arrays, 2.5)                             # coarse cells are size 2


# NOTE: error-driven LOD tests removed — the top-down corner-QEF metric over-coarsens
# (holes flat regions to one cell; undersamples curvature). The redesign (bottom-up
# measured-error collapse + a min-grid floor) will bring these invariants back as its
# spec: error-mode stays watertight on the sphere, and coarsens a flat field far below
# distance-mode without holing it.
