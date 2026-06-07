class_name OctreeMesher

# Dual Contouring directly over a VoxelOctree — the storage octree IS the render octree
# (no clipmap, no LOD bands, no inconsistent mips). This file is the first half: one
# vertex per surface leaf, placed on the isosurface from the leaf's corner crossings.
# The crack-free edge stitch (point-location across leaf-size jumps, as in the C++
# DCOctreeMesher) is the next piece.

# 12 cube edges as corner-index pairs (xyz bits — matches VoxelOctree.CORNERS).
const EDGES := [
    [0, 1], [2, 3], [4, 5], [6, 7],
    [0, 2], [1, 3], [4, 6], [5, 7],
    [0, 4], [1, 5], [2, 6], [3, 7],
]


# One vertex per surface leaf: the mean of the leaf's edge crossings (DC mass point —
# good enough for smooth fields; QEF for sharp creases comes with the C++ port).
# Returns null when the leaf holds no sign change (a bulk uniform leaf).
static func leaf_vertex(leaf: VoxelOctree):
    var sum := Vector3.ZERO
    var n := 0
    for e in EDGES:
        var fa := leaf.corners[e[0]]
        var fb := leaf.corners[e[1]]
        if (fa < 0.0) == (fb < 0.0):
            continue
        var t := fa / (fa - fb)
        var pa := leaf.origin + VoxelOctree.CORNERS[e[0]] * leaf.size
        var pb := leaf.origin + VoxelOctree.CORNERS[e[1]] * leaf.size
        sum += pa.lerp(pb, t)
        n += 1
    return null if n == 0 else sum / float(n)


static func surface_vertices(root: VoxelOctree) -> PackedVector3Array:
    var leaves: Array = []
    root.collect_leaves(leaves)
    var verts := PackedVector3Array()
    for leaf in leaves:
        var v = leaf_vertex(leaf)
        if v != null:
            verts.append(v)
    return verts
