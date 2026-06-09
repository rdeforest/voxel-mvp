class_name DCEditSplicer

# Pure mesh-array surgery for incremental edit patching (no Node/engine access, so it's
# unit-testable). Given the cached full-clipmap mesh (Mesh.ARRAY_* + a per-triangle world
# owner-cell origin) and a freshly re-meshed patch over a core box, it:
#   1. drops the cached triangles whose owner cell lies inside [core_min, core_max),
#   2. appends the patch's triangles, shifted from sub-local into cache-root-local space,
#   3. compacts to only the referenced vertices (so repeated edits don't grow the pool).
# The uniform 1m fine core guarantees the patch's per-cell vertices match the full build's,
# so the boundary between kept and patched triangles is seam-coincident (crack-free). See
# test/test_dc_incremental_splice.gd for the crack-free guarantee and test_dc_edit_splicer
# for this surgery.

static func _in_box(o: Vector3, lo: Vector3i, hi: Vector3i) -> bool:
    return o.x >= lo.x and o.x < hi.x and o.y >= lo.y and o.y < hi.y and o.z >= lo.z and o.z < hi.z


# Returns {"arrays": Mesh.ARRAY_* Array, "owners": PackedVector3Array} for the spliced mesh.
static func splice(cache_arrays: Array, cache_owners: PackedVector3Array, cache_origin: Vector3i,
        core_min: Vector3i, core_max: Vector3i, sub_origin: Vector3i,
        patch: Array, patch_owners: PackedVector3Array) -> Dictionary:
    var cv: PackedVector3Array = cache_arrays[Mesh.ARRAY_VERTEX]
    var cn: PackedVector3Array = cache_arrays[Mesh.ARRAY_NORMAL]
    var ci: PackedInt32Array   = cache_arrays[Mesh.ARRAY_INDEX]
    var cc := PackedColorArray()
    if cache_arrays[Mesh.ARRAY_COLOR] != null:
        cc = cache_arrays[Mesh.ARRAY_COLOR]
    var has_color := cc.size() == cv.size() and cv.size() > 0

    # Vertex pool: cached verts, then patch verts shifted into cache-root-local space.
    var verts := cv.duplicate()
    var normals := cn.duplicate()
    var colors := cc.duplicate()
    var base := cv.size()
    if not patch.is_empty():
        var offset := Vector3(sub_origin - cache_origin)
        var pv: PackedVector3Array = patch[Mesh.ARRAY_VERTEX]
        var pn: PackedVector3Array = patch[Mesh.ARRAY_NORMAL]
        var pc := PackedColorArray()
        if patch[Mesh.ARRAY_COLOR] != null:
            pc = patch[Mesh.ARRAY_COLOR]
        for i in pv.size():
            verts.append(pv[i] + offset)
            normals.append(pn[i])
            if has_color:
                colors.append(pc[i] if i < pc.size() else Color(0, 0, 0, 1))

    # Indices + owners: kept cached triangles (owner outside core) then all patch triangles.
    var out_idx := PackedInt32Array()
    var out_own := PackedVector3Array()
    for t in cache_owners.size():
        if _in_box(cache_owners[t], core_min, core_max):
            continue
        out_idx.append(ci[t * 3]); out_idx.append(ci[t * 3 + 1]); out_idx.append(ci[t * 3 + 2])
        out_own.append(cache_owners[t])
    if not patch.is_empty():
        var pi: PackedInt32Array = patch[Mesh.ARRAY_INDEX]
        @warning_ignore("integer_division")
        for t in pi.size() / 3:
            out_idx.append(pi[t * 3] + base); out_idx.append(pi[t * 3 + 1] + base); out_idx.append(pi[t * 3 + 2] + base)
            out_own.append(patch_owners[t])

    # Compact to referenced vertices.
    var vmap := {}
    var nv := PackedVector3Array()
    var nn := PackedVector3Array()
    var ncol := PackedColorArray()
    for j in out_idx.size():
        var old := out_idx[j]
        if not vmap.has(old):
            vmap[old] = nv.size()
            nv.append(verts[old]); nn.append(normals[old])
            if has_color:
                ncol.append(colors[old])
        out_idx[j] = vmap[old]

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = nv
    arrays[Mesh.ARRAY_NORMAL] = nn
    if has_color:
        arrays[Mesh.ARRAY_COLOR] = ncol
    arrays[Mesh.ARRAY_INDEX] = out_idx
    return {"arrays": arrays, "owners": out_own}
