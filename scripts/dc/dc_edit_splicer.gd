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

static func _in_box(point: Vector3, box_min: Vector3i, box_max: Vector3i) -> bool:
    return point.x >= box_min.x and point.x < box_max.x \
        and point.y >= box_min.y and point.y < box_max.y \
        and point.z >= box_min.z and point.z < box_max.z

# Triangles are 3 indices; this is their count for an index array of size n.
static func _first_third(n: int) -> int:
    @warning_ignore("integer_division")
    return n / 3

# Copy triangle `tri`'s three indices from `source` into `dest`, shifted by `base`.
static func _append_triangle(dest: PackedInt32Array, source: PackedInt32Array, tri: int, base: int) -> void:
    dest.append(source[tri * 3] + base)
    dest.append(source[tri * 3 + 1] + base)
    dest.append(source[tri * 3 + 2] + base)


# Returns {"arrays": Mesh.ARRAY_* Array, "owners": PackedVector3Array} for the spliced mesh.
static func splice(cache_arrays: Array, cache_owners: PackedVector3Array, cache_origin: Vector3i,
        core_min: Vector3i, core_max: Vector3i, sub_origin: Vector3i,
        patch: Array, patch_owners: PackedVector3Array) -> Dictionary:
    var cache_verts:   PackedVector3Array = cache_arrays[Mesh.ARRAY_VERTEX]
    var cache_normals: PackedVector3Array = cache_arrays[Mesh.ARRAY_NORMAL]
    var cache_indices: PackedInt32Array   = cache_arrays[Mesh.ARRAY_INDEX]
    var cache_colors := PackedColorArray()
    if cache_arrays[Mesh.ARRAY_COLOR] != null:
        cache_colors = cache_arrays[Mesh.ARRAY_COLOR]
    var has_color := cache_colors.size() == cache_verts.size() and cache_verts.size() > 0

    # Vertex pool: the cached verts, then the patch's verts shifted into cache-root-local
    # space. patch_vertex_base is where the patch's verts start, so its indices can be offset.
    var pool_verts   := cache_verts.duplicate()
    var pool_normals := cache_normals.duplicate()
    var pool_colors  := cache_colors.duplicate()
    var patch_vertex_base := cache_verts.size()
    if not patch.is_empty():
        var patch_offset := Vector3(sub_origin - cache_origin)
        var patch_verts:   PackedVector3Array = patch[Mesh.ARRAY_VERTEX]
        var patch_normals: PackedVector3Array = patch[Mesh.ARRAY_NORMAL]
        var patch_colors := PackedColorArray()
        if patch[Mesh.ARRAY_COLOR] != null:
            patch_colors = patch[Mesh.ARRAY_COLOR]
        for i in patch_verts.size():
            pool_verts.append(patch_verts[i] + patch_offset)
            pool_normals.append(patch_normals[i])
            if has_color:
                pool_colors.append(patch_colors[i] if i < patch_colors.size() else Color(0, 0, 0, 1))

    # Indices + owners: kept cached triangles (owner outside the core) then all patch triangles.
    var out_indices := PackedInt32Array()
    var out_owners  := PackedVector3Array()
    for tri in cache_owners.size():
        if _in_box(cache_owners[tri], core_min, core_max):
            continue
        _append_triangle(out_indices, cache_indices, tri, 0)
        out_owners.append(cache_owners[tri])
    if not patch.is_empty():
        var patch_indices: PackedInt32Array = patch[Mesh.ARRAY_INDEX]
        for tri in _first_third(patch_indices.size()):
            _append_triangle(out_indices, patch_indices, tri, patch_vertex_base)
            out_owners.append(patch_owners[tri])

    # Compact to only the referenced vertices.
    var vertex_map := {}
    var out_verts   := PackedVector3Array()
    var out_normals := PackedVector3Array()
    var out_colors  := PackedColorArray()
    for slot in out_indices.size():
        var src := out_indices[slot]
        if not vertex_map.has(src):
            vertex_map[src] = out_verts.size()
            out_verts.append(pool_verts[src])
            out_normals.append(pool_normals[src])
            if has_color:
                out_colors.append(pool_colors[src])
        out_indices[slot] = vertex_map[src]

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = out_verts
    arrays[Mesh.ARRAY_NORMAL] = out_normals
    if has_color:
        arrays[Mesh.ARRAY_COLOR] = out_colors
    arrays[Mesh.ARRAY_INDEX] = out_indices
    return {"arrays": arrays, "owners": out_owners}
