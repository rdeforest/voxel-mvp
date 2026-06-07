class_name OctreeMesher

# Dual Contouring directly over a VoxelOctree — the storage octree IS the render octree
# (no clipmap, no LOD bands, no inconsistent mips; that whole bug class is gone by
# construction). One vertex per surface leaf, stitched crack-free by point-location:
# the smallest cell around each surface edge owns it, and a coarser neighbour found
# twice collapses the quad to a triangle, so leaf-size jumps stitch seamlessly. Ported
# from the C++ DCOctreeMesher; GDScript prototype until the storage octree is in C++.

const EDGES := [
    [0, 1], [2, 3], [4, 5], [6, 7],
    [0, 2], [1, 3], [4, 6], [5, 7],
    [0, 4], [1, 5], [2, 6], [3, 7],
]
const RING := [[-1, -1], [1, -1], [1, 1], [-1, 1]]   # the 4 cells around an edge


static func _axis(i: int, a: float) -> Vector3:
    return Vector3(a, 0, 0) if i == 0 else (Vector3(0, a, 0) if i == 1 else Vector3(0, 0, a))


# One vertex per surface leaf: mean of the leaf's edge crossings (DC mass point — fine
# for smooth fields; QEF for sharp creases lands with the C++ port). null if no surface.
static func leaf_vertex(leaf: VoxelOctree):
    var sum := Vector3.ZERO
    var n := 0
    for e in EDGES:
        var fa := leaf.corners[e[0]]
        var fb := leaf.corners[e[1]]
        if (fa < 0.0) == (fb < 0.0):
            continue
        var pa := leaf.origin + VoxelOctree.CORNERS[e[0]] * leaf.size
        var pb := leaf.origin + VoxelOctree.CORNERS[e[1]] * leaf.size
        sum += pa.lerp(pb, fa / (fa - fb))
        n += 1
    return null if n == 0 else sum / float(n)


# Outward normal (SDF increases outward): the leaf's trilinear gradient from its corners.
static func leaf_normal(leaf: VoxelOctree) -> Vector3:
    var c := leaf.corners
    var g := Vector3(
        (c[1] - c[0]) + (c[3] - c[2]) + (c[5] - c[4]) + (c[7] - c[6]),
        (c[2] - c[0]) + (c[3] - c[1]) + (c[6] - c[4]) + (c[7] - c[5]),
        (c[4] - c[0]) + (c[5] - c[1]) + (c[6] - c[2]) + (c[7] - c[3]))
    return g.normalized() if g.length_squared() > 0.0 else Vector3.UP


static func surface_vertices(root: VoxelOctree) -> PackedVector3Array:
    var leaves: Array = []
    root.collect_leaves(leaves)
    var verts := PackedVector3Array()
    for leaf in leaves:
        var v = leaf_vertex(leaf)
        if v != null:
            verts.append(v)
    return verts


# Full mesh: {verts: PackedVector3Array, indices: PackedInt32Array}.
static func mesh(root: VoxelOctree) -> Dictionary:
    var leaves: Array = []
    root.collect_leaves(leaves)
    var verts := PackedVector3Array()
    for leaf in leaves:
        var v = leaf_vertex(leaf)
        leaf.vertex = -1
        if v != null:
            leaf.vertex = verts.size()
            verts.append(v)
    var idx := PackedInt32Array()
    for leaf in leaves:
        if leaf.vertex >= 0:
            _stitch_leaf(root, leaf, verts, idx)
    return {"verts": verts, "indices": idx}


static func _stitch_leaf(root: VoxelOctree, leaf: VoxelOctree, verts: PackedVector3Array,
        idx: PackedInt32Array) -> void:
    for axis in 3:
        var u := (axis + 1) % 3
        var w := (axis + 2) % 3
        for su in 2:
            for sw in 2:
                _try_edge(root, leaf, axis, u, w, su, sw, verts, idx)


static func _try_edge(root: VoxelOctree, leaf: VoxelOctree, axis: int, u: int, w: int,
        su: int, sw: int, verts: PackedVector3Array, idx: PackedInt32Array) -> void:
    var s := leaf.size
    var lo := leaf.origin + _axis(u, su * s) + _axis(w, sw * s)
    var hi := lo + _axis(axis, s)
    var fa := root.sample(lo)
    var fb := root.sample(hi)
    if fa == VoxelOctree.EMPTY or fb == VoxelOctree.EMPTY or (fa < 0.0) == (fb < 0.0):
        return
    var mid := (lo + hi) * 0.5
    var eps := s * 0.25
    var cells: Array = []
    for k in 4:
        cells.append(root.find_leaf(mid + _axis(u, RING[k][0] * eps) + _axis(w, RING[k][1] * eps)))
    if not _owns_edge(leaf, cells):
        return
    var ring: Array = []
    for ci in cells:
        if ci == null or ci.vertex < 0:
            return
        if ring.is_empty() or ring[-1] != ci.vertex:
            ring.append(ci.vertex)
    if ring.size() > 1 and ring[0] == ring[-1]:
        ring.pop_back()
    if ring.size() >= 3:
        _emit_poly(ring, leaf_normal(leaf), verts, idx)


# This leaf owns the edge iff it is a smallest cell around it and, among equal-smallest,
# the lexicographically least origin — so exactly one cell emits.
static func _owns_edge(leaf: VoxelOctree, cells: Array) -> bool:
    var min_size := leaf.size
    for ci in cells:
        if ci != null and ci.size < min_size:
            min_size = ci.size
    if leaf.size != min_size:
        return false
    for ci in cells:
        if ci != null and ci.size == min_size and _origin_less(ci.origin, leaf.origin):
            return false
    return true


static func _origin_less(a: Vector3, b: Vector3) -> bool:
    if a.x != b.x:  return a.x < b.x
    if a.y != b.y:  return a.y < b.y
    return a.z < b.z


static func _emit_poly(ring: Array, outward: Vector3, verts: PackedVector3Array,
        idx: PackedInt32Array) -> void:
    _emit_tri(ring[0], ring[1], ring[2], outward, verts, idx)
    if ring.size() == 4:
        _emit_tri(ring[0], ring[2], ring[3], outward, verts, idx)


# Wind each triangle so its front face points `outward` (per-triangle — a quad over a
# size jump is non-planar, so one flip per quad would leave a triangle back-facing).
# Godot is CW-from-front, so reverse when the right-hand normal already points outward.
static func _emit_tri(i0: int, i1: int, i2: int, outward: Vector3,
        verts: PackedVector3Array, idx: PackedInt32Array) -> void:
    var n := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
    if n.dot(outward) >= 0.0:
        idx.append(i0); idx.append(i2); idx.append(i1)
    else:
        idx.append(i0); idx.append(i1); idx.append(i2)
