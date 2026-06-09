extends GutTest

# Surface-sparse build (prune_safety > 0): the mesher must skip provably-empty regions so
# the tree is O(surface) not O(volume) — WITHOUT punching holes on real ridged terrain (the
# [[dc-sdf-not-unit-distance]] hazard). Proof: mesh the same 128m cube of the actual
# generator dense and pruned; the pruned mesh must be just as watertight as the dense one
# and cover the same surface, while building dramatically faster.

const GRAPH := "res://assets/generators/terrain.tres"
const SIZE  := 128                         # depth-7 octree root, 1m floor (the fine-core case)
const DIM   := SIZE + 1
const DEPTH := 7
const WALL_EPS := 2.0

var ORIGIN: Vector3i


func before_all() -> void:
    var gen: VoxelGenerator = load(GRAPH)
    var h := 512
    var y0 := -192
    var buf := VoxelBuffer.new()
    buf.create(4, h, 4)
    gen.generate_block(buf, Vector3i(-2, y0, -2), 0)
    var ch := VoxelBuffer.CHANNEL_SDF
    var surf := y0 + h / 2
    for y in range(h - 2, 0, -1):
        if buf.get_voxel_f(2, y, 2, ch) < 0.0 and buf.get_voxel_f(2, y + 1, 2, ch) >= 0.0:
            surf = y0 + y
            break
    ORIGIN = Vector3i(-SIZE / 2, surf - SIZE / 2, -SIZE / 2)


func _bake() -> PackedFloat32Array:
    var buf := VoxelBuffer.new()
    buf.create(DIM, DIM, DIM)
    (load(GRAPH) as VoxelGenerator).generate_block(buf, Vector3(ORIGIN), 0)
    var sdf := PackedFloat32Array()
    sdf.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                sdf[i] = buf.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
                i += 1
    return sdf


func _on_wall(v: Vector3) -> bool:
    return absf(v.x - ORIGIN.x) < WALL_EPS or absf(v.x - (ORIGIN.x + SIZE)) < WALL_EPS \
        or absf(v.y - ORIGIN.y) < WALL_EPS or absf(v.y - (ORIGIN.y + SIZE)) < WALL_EPS \
        or absf(v.z - ORIGIN.z) < WALL_EPS or absf(v.z - (ORIGIN.z + SIZE)) < WALL_EPS


func _mesh(data: PackedFloat32Array, prune: float) -> Dictionary:
    var t0 := Time.get_ticks_msec()
    # One uniform level (the fine-core case), error-driven off so only the prune changes the
    # tree. center far / half0 huge => single level everywhere.
    var arrays := DCOctreeMesher.new().mesh_clipmap(
        [data], DIM, PackedVector3Array([Vector3(ORIGIN)]), PackedFloat32Array([1.0]),
        Vector3(ORIGIN), 1e9, DEPTH, Vector3(ORIGIN), 0.0, 0.0, false, Vector3i.ZERO,
        [], PackedColorArray(), false, prune)
    var ms := Time.get_ticks_msec() - t0
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if not arrays.is_empty() else PackedVector3Array()
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX] if not arrays.is_empty() else PackedInt32Array()
    var counts := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
            var k := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[k] = counts.get(k, 0) + 1
    var interior := 0
    for k in counts:
        if counts[k] == 1 and not (_on_wall(verts[k.x]) and _on_wall(verts[k.y])):
            interior += 1
    return {"ms": ms, "tris": idx.size() / 3, "interior": interior, "verts": verts.size()}


func test_pruned_matches_dense_and_is_faster() -> void:
    var data := _bake()
    var dense := _mesh(data, 0.0)
    var pruned := _mesh(data, 1.5)
    gut.p("dense : %d ms  tris=%d  interior_holes=%d" % [dense.ms, dense.tris, dense.interior])
    gut.p("pruned: %d ms  tris=%d  interior_holes=%d" % [pruned.ms, pruned.tris, pruned.interior])
    assert_gt(dense.tris, 1000, "dense actually meshed the mountain")
    # The prune must not add holes beyond the dense baseline (ridged ridgelines crack a
    # little either way; the prune mustn't make it worse).
    assert_lte(pruned.interior, dense.interior + 2, "prune doesn't punch new holes on ridged terrain")
    # Same surface: triangle counts within 3% (the prune changes only empty regions).
    assert_almost_eq(int(pruned.tris), int(dense.tris), int(dense.tris * 0.03),
        "pruned mesh covers the same surface as dense")
    # The whole point: dramatically less work.
    assert_lt(pruned.ms, dense.ms * 0.5, "surface-sparse build is at least 2x faster")
