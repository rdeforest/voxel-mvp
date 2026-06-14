extends GutTest

# DCEditSplicer array surgery: drop cached triangles owned inside the core box, append the
# patch's (shifted by sub_origin - cache_origin), compact to referenced verts. (The crack-
# free guarantee is test_dc_incremental_splice; this checks the bookkeeping.)

const CORE_MIN := Vector3i(-1, -1, -1)
const CORE_MAX := Vector3i(1, 1, 1)        # contains (0,0,0), excludes (100,0,0)
const CACHE_ORIGIN := Vector3i.ZERO
const SUB_ORIGIN := Vector3i(10, 0, 0)     # offset = (10,0,0)


# A mesh of `tri_count` unshared triangles (3 verts each) with the given per-triangle owners.
func _mesh(owners: Array) -> Dictionary:
    var verts := PackedVector3Array()
    var normals := PackedVector3Array()
    var indices := PackedInt32Array()
    for t in owners.size():
        for k in 3:
            verts.append(Vector3(t, k, 0))
            normals.append(Vector3.UP)
            indices.append(t * 3 + k)
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var ow := PackedVector3Array()
    for o in owners:
        ow.append(o)
    return {"arrays": arrays, "owners": ow}


func _valid_compact(arrays: Array) -> bool:
    var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
    var nv: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    var used := {}
    for i in idx:
        if i < 0 or i >= nv:
            return false
        used[i] = true
    return used.size() == nv   # every vertex referenced (fully compacted)


func test_swaps_core_triangles_for_patch() -> void:
    var inb := Vector3(0, 0, 0)
    var out := Vector3(100, 0, 0)
    var cache := _mesh([inb, out, inb, out])    # tris 0,2 in core; 1,3 outside
    var patch := _mesh([inb])                    # one replacement triangle, owner in core

    var r := DCEditSplicer.splice(
        {"arrays": cache.arrays, "owners": cache.owners, "sizes": PackedFloat32Array()},
        {"arrays": patch.arrays, "owners": patch.owners, "sizes": PackedFloat32Array()},
        CORE_MIN, CORE_MAX, Vector3(SUB_ORIGIN - CACHE_ORIGIN))
    var idx: PackedInt32Array = r.arrays[Mesh.ARRAY_INDEX]
    var ow: PackedVector3Array = r.owners
    assert_eq(idx.size(), 9, "2 kept + 1 patch = 3 triangles")
    assert_eq(ow.size(), 3, "one owner per surviving triangle")
    assert_eq(ow.count(out), 2, "both out-of-core triangles kept")
    assert_eq(ow.count(inb), 1, "core triangles replaced by the single patch triangle")
    assert_true(_valid_compact(r.arrays), "indices valid and vertex pool fully compacted")
    # Patch vertex (t=0,k=1) = (0,1,0) shifted by (10,0,0) -> (10,1,0) must be present.
    assert_true((r.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).has(Vector3(10, 1, 0)),
        "patch verts land in cache-root-local space (shifted)")


func test_empty_patch_is_removal_only() -> void:
    var inb := Vector3(0, 0, 0)
    var out := Vector3(100, 0, 0)
    var cache := _mesh([inb, out, inb])          # 2 in core, 1 outside
    var r := DCEditSplicer.splice(
        {"arrays": cache.arrays, "owners": cache.owners, "sizes": PackedFloat32Array()},
        {"arrays": [], "owners": PackedVector3Array(), "sizes": PackedFloat32Array()},
        CORE_MIN, CORE_MAX, Vector3(SUB_ORIGIN - CACHE_ORIGIN))
    assert_eq((r.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 3, "only the out-of-core triangle remains")
    assert_eq(r.owners.size(), 1)
    assert_true(_valid_compact(r.arrays), "removal-only result still compact")
