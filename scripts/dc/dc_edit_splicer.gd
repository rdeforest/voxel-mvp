class_name DCEditSplicer

# Replaces the cached terrain mesh's triangles inside an edit's CORE box with a freshly meshed
# patch, leaving everything outside it untouched. Pure array surgery — no engine access — so the
# crack-free guarantee (test_dc_incremental_splice) and the surgery itself (test_dc_edit_splicer)
# stay unit-testable.
#
# A "mesh" is a bundle: { arrays = Mesh.ARRAY_*, owners = per-triangle world owner-cell origins,
# sizes = per-triangle owner-cell sizes }. The patch was meshed in its own local space, so its
# vertices move into the cache's space by `patch_shift`.

static func splice(cache: Dictionary, patch: Dictionary,
        core_min: Vector3i, core_max: Vector3i, patch_shift: Vector3) -> Dictionary:
    var pool := _vertex_pool(cache, patch, patch_shift)
    var triangles := _kept_cache_triangles(cache, core_min, core_max)
    _append(triangles, _patch_triangles(patch, _vertex_count(cache)))
    return _compacted(pool, triangles)


# --- vertices: the cache's, then the patch's shifted into cache space ---

static func _vertex_pool(cache: Dictionary, patch: Dictionary, shift: Vector3) -> Dictionary:
    var verts   := PackedVector3Array(cache.arrays[Mesh.ARRAY_VERTEX])
    var normals := PackedVector3Array(cache.arrays[Mesh.ARRAY_NORMAL])
    var colors  := _colors_of(cache.arrays)
    var has_color := colors.size() == verts.size() and verts.size() > 0
    for i in _vertex_count(patch):
        verts.append(patch.arrays[Mesh.ARRAY_VERTEX][i] + shift)
        normals.append(patch.arrays[Mesh.ARRAY_NORMAL][i])
        if has_color:
            colors.append(_color_at(patch.arrays, i))
    return {"verts": verts, "normals": normals, "colors": colors, "has_color": has_color}


# --- triangles: index-triples + owner + size, referencing the vertex pool ---

static func _kept_cache_triangles(cache: Dictionary, core_min: Vector3i, core_max: Vector3i) -> Dictionary:
    var kept := _no_triangles()
    var indices: PackedInt32Array = cache.arrays[Mesh.ARRAY_INDEX]
    for tri in cache.owners.size():
        if not _inside(cache.owners[tri], core_min, core_max):
            _add(kept, indices, tri, 0, cache.owners[tri], _size_at(cache.sizes, tri))
    return kept

static func _patch_triangles(patch: Dictionary, vertex_base: int) -> Dictionary:
    var added := _no_triangles()
    if _vertex_count(patch) == 0:
        return added
    var indices: PackedInt32Array = patch.arrays[Mesh.ARRAY_INDEX]
    for tri in _triangle_count(indices):
        _add(added, indices, tri, vertex_base, patch.owners[tri], _size_at(patch.sizes, tri))
    return added


# --- compaction: keep only the vertices the surviving triangles reference ---

static func _compacted(pool: Dictionary, triangles: Dictionary) -> Dictionary:
    var slot_of := {}
    var verts   := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors  := PackedColorArray()
    var indices: PackedInt32Array = triangles.indices
    for slot in indices.size():
        var src: int = indices[slot]
        if not slot_of.has(src):
            slot_of[src] = verts.size()
            verts.append(pool.verts[src])
            normals.append(pool.normals[src])
            if pool.has_color:
                colors.append(pool.colors[src])
        indices[slot] = slot_of[src]
    return {"arrays": _surface(verts, normals, colors, indices, pool.has_color),
            "owners": triangles.owners, "sizes": triangles.sizes}


# --- tiny helpers, each named for the one thing it answers ---

static func _vertex_count(mesh: Dictionary) -> int:
    var arrays: Array = mesh.arrays
    return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if not arrays.is_empty() else 0

static func _triangle_count(indices: PackedInt32Array) -> int:
    @warning_ignore("integer_division")
    return indices.size() / 3

static func _inside(point: Vector3, lo: Vector3i, hi: Vector3i) -> bool:
    return point.x >= lo.x and point.x < hi.x \
       and point.y >= lo.y and point.y < hi.y \
       and point.z >= lo.z and point.z < hi.z

static func _no_triangles() -> Dictionary:
    return {"indices": PackedInt32Array(), "owners": PackedVector3Array(), "sizes": PackedFloat32Array()}

static func _add(triangles: Dictionary, source: PackedInt32Array, tri: int, vertex_base: int,
        owner: Vector3, size: float) -> void:
    triangles.indices.append(source[tri * 3]     + vertex_base)
    triangles.indices.append(source[tri * 3 + 1] + vertex_base)
    triangles.indices.append(source[tri * 3 + 2] + vertex_base)
    triangles.owners.append(owner)
    triangles.sizes.append(size)

static func _append(into: Dictionary, more: Dictionary) -> void:
    into.indices.append_array(more.indices)
    into.owners.append_array(more.owners)
    into.sizes.append_array(more.sizes)

static func _colors_of(arrays: Array) -> PackedColorArray:
    return PackedColorArray(arrays[Mesh.ARRAY_COLOR]) if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()

static func _color_at(arrays: Array, i: int) -> Color:
    var colors := _colors_of(arrays)
    return colors[i] if i < colors.size() else Color(0, 0, 0, 1)

static func _size_at(sizes: PackedFloat32Array, tri: int) -> float:
    return sizes[tri] if tri < sizes.size() else 1.0

static func _surface(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
        indices: PackedInt32Array, has_color: bool) -> Array:
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    if has_color:
        arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_INDEX] = indices
    return arrays
