extends GutTest

# Incremental edit patching: re-meshing a sub-box (DCOctreeMesher.mesh_subregion) and
# splicing it into a cached full mesh must stay watertight — no cracks at the patch seam.
# The uniform 1m fine core makes the patch's per-cell vertices identical to the full
# build's, so removing the core box's triangles and dropping in the patch's leaves the
# surface sealed. A watertight sphere fully inside the region is the probe: the full mesh
# is closed (0 boundary edges), and the splice must keep it closed.

const ROOT   := 64
const DIM    := ROOT + 1
const DEPTH  := 6
const CENTER := Vector3(32, 32, 32)
const RADIUS := 20.0

# A core box straddling the +X pole (x ≈ 52). The dimple edit below has radius 5 about
# (52,32,32); the core must CONTAIN its whole influence (else kept cache triangles next to
# the edit are stale → cracks — the real rule for sizing an edit patch). Core ±7, with a
# 5-cell apron out to the sub cube for stitching.
const CORE_MIN := Vector3i(45, 25, 25)
const CORE_MAX := Vector3i(59, 39, 39)
const SUB_ORIGIN := Vector3i(40, 20, 20)
const SUB_SIZE := 32
const SUB_DIM := SUB_SIZE + 1


func _grid(dim: int, origin: Vector3i, dent: float) -> PackedFloat32Array:
    # Sphere SDF over a dim^3 1m grid. `dent` carves a small dimple at the +X pole so the
    # "edited" field differs from the cached one inside the core box.
    var data := PackedFloat32Array()
    data.resize(dim * dim * dim)
    var i := 0
    for z in dim:
        for y in dim:
            for x in dim:
                var p := Vector3(origin.x + x, origin.y + y, origin.z + z)
                var d := p.distance_to(CENTER) - RADIUS
                if dent > 0.0:
                    d += dent * maxf(0.0, 1.0 - p.distance_to(Vector3(52, 32, 32)) / 5.0)
                data[i] = d
                i += 1
    return data


func _full(dent: float) -> Dictionary:
    var m := DCOctreeMesher.new()
    var arrays := m.mesh_clipmap([_grid(DIM, Vector3i.ZERO, dent)], DIM,
            PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
            CENTER, 1e9, DEPTH)
    return {"arrays": arrays, "owners": m.get_last_triangle_owners()}


func _patch(dent: float) -> Dictionary:
    # The data grid covers the sub cube indexed in LOCAL coords (grid[0] = world SUB_ORIGIN),
    # so data_origin is ZERO — the octree builds at local 0..SUB_SIZE; owners come out world
    # (local + world_origin=SUB_ORIGIN), vertices local (caller shifts by SUB_ORIGIN).
    var m := DCOctreeMesher.new()
    var arrays := m.mesh_subregion(_grid(SUB_DIM, SUB_ORIGIN, dent), SUB_DIM,
            Vector3.ZERO, 1.0, SUB_ORIGIN, SUB_SIZE, CORE_MIN, CORE_MAX)
    return {"arrays": arrays, "owners": m.get_last_triangle_owners()}


func _in_core(o: Vector3) -> bool:
    return o.x >= CORE_MIN.x and o.x < CORE_MAX.x and o.y >= CORE_MIN.y and o.y < CORE_MAX.y \
        and o.z >= CORE_MIN.z and o.z < CORE_MAX.z


# Triangles as triples of world positions: cached full minus its core-owned tris, plus the
# patch's tris (shifted from sub-local to world).
func _spliced_tris(full: Dictionary, patch: Dictionary) -> Array:
    var tris: Array = []
    var fv: PackedVector3Array = full.arrays[Mesh.ARRAY_VERTEX]
    var fi: PackedInt32Array   = full.arrays[Mesh.ARRAY_INDEX]
    var fo: PackedVector3Array = full.owners
    for t in range(fo.size()):
        if _in_core(fo[t]):
            continue
        tris.append([fv[fi[t * 3]], fv[fi[t * 3 + 1]], fv[fi[t * 3 + 2]]])
    var pv: PackedVector3Array = patch.arrays[Mesh.ARRAY_VERTEX]
    var pi: PackedInt32Array   = patch.arrays[Mesh.ARRAY_INDEX]
    var off := Vector3(SUB_ORIGIN)
    for t in range(pi.size() / 3):
        tris.append([pv[pi[t * 3]] + off, pv[pi[t * 3 + 1]] + off, pv[pi[t * 3 + 2]] + off])
    return tris


# Weld vertices by quantised position, then count edges used once (boundary) / >2 (nonmanifold).
func _audit(tris: Array) -> Dictionary:
    var key := func(v: Vector3) -> Vector3i:
        return Vector3i(roundi(v.x * 16.0), roundi(v.y * 16.0), roundi(v.z * 16.0))
    var ids := {}
    var counts := {}
    for tri in tris:
        var vi: Array = []
        for v in tri:
            var k: Vector3i = key.call(v)
            if not ids.has(k):
                ids[k] = ids.size()
            vi.append(ids[k])
        for e in [[vi[0], vi[1]], [vi[1], vi[2]], [vi[2], vi[0]]]:
            var ek := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[ek] = counts.get(ek, 0) + 1
    var boundary := 0
    var nonmanifold := 0
    for k in counts:
        if counts[k] == 1:   boundary += 1
        elif counts[k] > 2:  nonmanifold += 1
    return {"boundary": boundary, "nonmanifold": nonmanifold, "tris": tris.size()}


func test_full_sphere_is_watertight() -> void:
    var full := _full(0.0)
    var a := _audit(_spliced_tris(full, {"arrays": _empty(), "owners": PackedVector3Array()}))
    # (no patch) — this is full-minus-core, which SHOULD have a hole where the core was.
    assert_gt(a.boundary, 0, "removing the core's triangles opens a hole (sanity: removal works)")


func test_splice_same_data_watertight() -> void:
    var full := _full(0.0)
    var patch := _patch(0.0)
    assert_gt((patch.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 0, "patch produced triangles")
    var a := _audit(_spliced_tris(full, patch))
    gut.p("splice (same data): tris=%d boundary=%d nonmanifold=%d" % [a.tris, a.boundary, a.nonmanifold])
    assert_eq(a.boundary, 0, "patch re-seals the hole — watertight, no crack at the seam")
    assert_eq(a.nonmanifold, 0, "manifold across the seam")


func test_splice_after_edit_watertight() -> void:
    var full := _full(0.0)          # cached, undented
    var patch := _patch(6.0)        # re-meshed with a dimple carved in the core
    var a := _audit(_spliced_tris(full, patch))
    gut.p("splice (edited core): tris=%d boundary=%d nonmanifold=%d" % [a.tris, a.boundary, a.nonmanifold])
    assert_eq(a.boundary, 0, "edited patch still seals to the unchanged surround — no crack")
    assert_eq(a.nonmanifold, 0, "manifold across the seam after an edit")


func _empty() -> Array:
    var a: Array = []
    a.resize(Mesh.ARRAY_MAX)
    a[Mesh.ARRAY_VERTEX] = PackedVector3Array()
    a[Mesh.ARRAY_INDEX] = PackedInt32Array()
    return a
