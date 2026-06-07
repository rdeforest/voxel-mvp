extends GutTest

# DC vertex placement over the storage octree: every surface-leaf vertex must sit on
# the imprinted isosurface (the storage octree meshes its own contents).

const ROOT := 16.0
const CENTER := Vector3(8, 8, 8)
const RADIUS := 5.0


func _sphere(p: Vector3) -> float:
    return p.distance_to(CENTER) - RADIUS


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


func test_octree_meshes_watertight() -> void:
    var t := VoxelOctree.new(Vector3.ZERO, ROOT)
    t.imprint(_sphere, 0.5, 1)
    var m := OctreeMesher.mesh(t)
    var verts: PackedVector3Array = m.verts
    var idx:   PackedInt32Array   = m.indices
    var a := _edge_audit(idx)
    var worst := 0.0
    for v in verts:
        worst = maxf(worst, absf(_sphere(v)))
    gut.p("mesh: verts=%d tris=%d boundary=%d nonmanifold=%d max_off=%.3f" % [
        verts.size(), idx.size() / 3, a["boundary"], a["nonmanifold"], worst])
    assert_gt(idx.size() / 3, 100, "the sphere is tessellated")
    assert_eq(a["boundary"], 0, "watertight — no boundary edges / holes")
    assert_eq(a["nonmanifold"], 0, "manifold — no edge shared by >2 triangles")
    assert_lt(worst, 0.5, "mesh hugs the imprinted sphere")


func test_vertices_lie_on_the_imprinted_surface() -> void:
    for min_leaf in [1.0, 0.5, 0.25]:
        var t := VoxelOctree.new(Vector3.ZERO, ROOT)
        t.imprint(_sphere, min_leaf, 1)
        var verts := OctreeMesher.surface_vertices(t)
        var worst := 0.0
        for v in verts:
            worst = maxf(worst, absf(_sphere(v)))   # distance off the true sphere
        gut.p("min_leaf=%.2f  surface verts=%d  max off-surface=%.3f" % [min_leaf, verts.size(), worst])
        assert_gt(verts.size(), 50, "the surface is tessellated")
        assert_lt(worst, min_leaf, "every vertex sits on the surface within a leaf")
