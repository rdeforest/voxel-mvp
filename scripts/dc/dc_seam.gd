class_name DcSeam
extends RefCounted

# Bite F2: stitch a Dual Contouring LOD seam. A fine block and a coarse block of
# the same field leave open boundary loops where the surface meets their shared
# face (DC vertices are off-grid, so the two resolutions don't line up). This
# builds the additive "transition band" that zippers the fine loop to the coarse
# loop, closing the crack. The band goes into the higher-res block's
# transition_surfaces[face] in the engine; here it's validated standalone.


# Oriented open-boundary loops of a triangle mesh. A boundary edge is a directed
# triangle edge whose reverse is absent; those edges chain into oriented loops
# (the open border of the surface). Returns Array of PackedInt32Array (vertex
# index rings).
static func open_loops(indices: PackedInt32Array) -> Array:
    var dir := {}                      # Vector2i(u,v) present
    for i in range(0, indices.size(), 3):
        var t := [indices[i], indices[i + 1], indices[i + 2]]
        for e in [[t[0], t[1]], [t[1], t[2]], [t[2], t[0]]]:
            dir[Vector2i(e[0], e[1])] = true
    var next := {}                     # u -> v for boundary edges
    for key in dir:
        if not dir.has(Vector2i(key.y, key.x)):
            next[key.x] = key.y
    var loops: Array = []
    var seen := {}
    for start in next:
        if seen.has(start):
            continue
        var loop := PackedInt32Array()
        var cur: int = start
        while next.has(cur) and not seen.has(cur):
            seen[cur] = true
            loop.append(cur)
            cur = next[cur]
        if loop.size() >= 3:
            loops.append(loop)
    return loops


# Newell normal of a vertex ring (robust for near-planar loops).
static func loop_normal(ring_pos: PackedVector3Array) -> Vector3:
    var n := Vector3.ZERO
    var count := ring_pos.size()
    for i in count:
        var a := ring_pos[i]
        var b := ring_pos[(i + 1) % count]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n.normalized() if n.length_squared() > 0.0 else Vector3.UP


# Zipper two position rings (fine -> coarse) into a triangle band. Returns
# {verts, indices}: verts = fine ring then coarse ring; indices triangulate the
# annulus so every ring edge is used once and diagonals are shared -> after
# welding with the two block meshes, the seam has no boundary edges.
static func stitch(fine: PackedVector3Array, coarse: PackedVector3Array) -> Dictionary:
    var cl := coarse
    # Match winding so the strip doesn't twist (the two loops border opposite
    # sides of the seam, so they're usually wound opposite).
    if loop_normal(fine).dot(loop_normal(cl)) < 0.0:
        cl = _reversed(cl)

    var m := fine.size()
    var n := cl.size()
    var verts := PackedVector3Array()
    verts.append_array(fine)
    verts.append_array(cl)
    var indices := PackedInt32Array()
    if m == 0 or n == 0:
        return {"verts": verts, "indices": indices}

    # Start the coarse walk at the vertex nearest fine[0] to avoid a long seam.
    var j0 := 0
    var best := INF
    for j in n:
        var d := fine[0].distance_squared_to(cl[j])
        if d < best:
            best = d
            j0 = j

    var i := 0
    var j := 0
    while i < m or j < n:
        var fi := i % m
        var ci := (j0 + j) % n
        var take_fine := i < m
        if i < m and j < n:
            var df := fine[(i + 1) % m].distance_squared_to(cl[ci])
            var dc := fine[fi].distance_squared_to(cl[(j0 + j + 1) % n])
            take_fine = df <= dc
        if take_fine:
            indices.append(fi); indices.append((i + 1) % m); indices.append(m + ci)
            i += 1
        else:
            indices.append(fi); indices.append(m + ci); indices.append(m + (j0 + j + 1) % n)
            j += 1
    return {"verts": verts, "indices": indices}


static func _reversed(p: PackedVector3Array) -> PackedVector3Array:
    var out := PackedVector3Array()
    out.resize(p.size())
    for i in p.size():
        out[i] = p[p.size() - 1 - i]
    return out
