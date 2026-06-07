extends GutTest

# DC vertex placement over the storage octree: every surface-leaf vertex must sit on
# the imprinted isosurface (the storage octree meshes its own contents).

const ROOT := 16.0
const CENTER := Vector3(8, 8, 8)
const RADIUS := 5.0


func _sphere(p: Vector3) -> float:
    return p.distance_to(CENTER) - RADIUS


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
