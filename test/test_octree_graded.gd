extends GutTest

# Distance-graded LOD: one octree spans the view, fine near the focus, coarse far —
# and still watertight across the size jumps (the point-location stitch). This is what
# lets a single octree cover the whole world affordably.

const ROOT := 64.0
const CENTER := Vector3(32, 32, 32)
const RADIUS := 24.0


func _graded(focus: Vector3) -> SparseVoxelOctree:
    var t := SparseVoxelOctree.new()
    t.setup(Vector3.ZERO, ROOT)
    t.imprint_sphere_graded(CENTER, RADIUS, focus, 0.5, 6.0, 1)   # near_leaf 0.5, band 6
    return t


# Vertices near the focus sit on the sphere far more tightly than vertices on the far
# side (finer leaves there) — that's the grading working.
func test_finer_near_the_focus() -> void:
    var focus := Vector3(56, 32, 32)                 # near the sphere's +X pole (world 56,32,32)
    var t := _graded(focus)
    var m := t.mesh()
    var verts: PackedVector3Array = m[Mesh.ARRAY_VERTEX]
    var near_err := 0.0
    var far_err := 0.0
    for v in verts:
        var off := absf(v.distance_to(CENTER) - RADIUS)
        if v.distance_to(focus) < 10.0:
            near_err = maxf(near_err, off)
        elif v.x < CENTER.x - 18.0:                  # the far (-X) side
            far_err = maxf(far_err, off)
    gut.p("graded: verts=%d  near-focus max_off=%.3f  far-side max_off=%.3f" % [
        verts.size(), near_err, far_err])
    assert_lt(near_err, 0.5, "near the focus, vertices hug the sphere (fine leaves)")
    assert_gt(far_err, near_err, "the far side is coarser (graded LOD)")


func test_graded_is_watertight() -> void:
    var t := _graded(Vector3(56, 32, 32))
    var idx: PackedInt32Array = t.mesh()[Mesh.ARRAY_INDEX]
    var counts := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
            var k := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[k] = counts.get(k, 0) + 1
    var boundary := 0
    var nonmanifold := 0
    for k in counts:
        if counts[k] == 1:   boundary += 1
        elif counts[k] > 2:  nonmanifold += 1
    assert_eq(boundary, 0, "graded octree stitches crack-free across LOD jumps")
    assert_eq(nonmanifold, 0, "and stays manifold")
