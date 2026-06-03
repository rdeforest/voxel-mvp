extends GutTest

# Crease-aware normal splitting: two triangles sharing an edge A-B. A sharp
# dihedral splits the shared vertices (one normal per face); a flat dihedral
# leaves them merged (one smooth normal).

const A := Vector3(0, 0, 0)
const B := Vector3(1, 0, 0)
const C := Vector3(0.5, 1, 0)      # tri0 in the z=0 plane

# tri0 = (A,B,C); tri1 = (B,A,D). Shared edge A-B.
var _indices := PackedInt32Array([0, 1, 2, 1, 0, 3])


func _mesh_with(d: Vector3) -> Dictionary:
    var verts := PackedVector3Array([A, B, C, d])
    return MeshNormals.with_crease_normals(verts, _indices)

func test_flat_pair_is_not_split():
    # D mirrors C across the edge -> the two triangles are coplanar.
    var r := _mesh_with(Vector3(0.5, -1, 0))
    assert_eq((r["verts"] as PackedVector3Array).size(), 4)   # A,B shared

func test_sharp_pair_splits_shared_vertices():
    # D lifts tri1 into the z axis -> 90 degree dihedral along A-B.
    var r := _mesh_with(Vector3(0.5, 0, 1))
    assert_eq((r["verts"] as PackedVector3Array).size(), 6)   # A and B each duplicated

func test_normals_are_unit_length():
    var r := _mesh_with(Vector3(0.5, 0, 1))
    for n in (r["normals"] as PackedVector3Array):
        assert_almost_eq(n.length(), 1.0, 0.0001)

func test_smooth_normals_used_verbatim_when_unsplit():
    var verts := PackedVector3Array([A, B, C, Vector3(0.5, -1, 0)])
    var smooth := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
    var r := MeshNormals.with_crease_normals(verts, _indices, smooth)
    for n in (r["normals"] as PackedVector3Array):
        assert_almost_eq(n, Vector3.UP, Vector3.ONE * 0.0001)
