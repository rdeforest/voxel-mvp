extends GutTest

# SPIKE (Exp 2): how long does it cost to cook a ConcavePolygonShape3D from a
# fine, body-local terrain tile? This is the main-thread cost that bounds the
# body-driven JIT collision budget — Godot can't cook trimesh shapes off-thread.
# Measures real terrain regions at two tile sizes; prints ms + triangle counts.
# Not a pass/fail test — it prints calibration numbers (asserts only sanity).

const ITERS := 30


func _generator() -> VoxelGeneratorNoise2D:
    var noise := FastNoiseLite.new()
    noise.seed = 1
    noise.fractal_lacunarity = 1.5
    var gen := VoxelGeneratorNoise2D.new()
    gen.height_range = 100.0
    gen.noise = noise
    return gen

func _bake(dim: int, origin: Vector3i) -> PackedFloat32Array:
    var buf := VoxelBuffer.new()
    buf.create(dim, dim, dim)
    _generator().generate_block(buf, Vector3(origin), 0)
    var data := PackedFloat32Array()
    data.resize(dim * dim * dim)
    var i := 0
    for z in dim:
        for y in dim:
            for x in dim:
                data[i] = buf.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
                i += 1
    return data

# Mesh a uniform fine tile of `size`^3 (depth = log2 size) of real terrain, then
# time cooking a ConcavePolygonShape3D from its triangle soup.
func _measure(size: int) -> void:
    var depth := int(round(log(size) / log(2.0)))
    var dim := size + 1
    var origin := Vector3i(-size / 2, -16, -size / 2)   # surface ~y=0 sits in the tile
    var data := _bake(dim, origin)
    var arrays := DCOctreeMesher.new().mesh_clipmap(
        [data], dim, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        Vector3.ZERO, 1e9, depth)
    assert_false(arrays.is_empty(), "tile meshed")
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array     = arrays[Mesh.ARRAY_INDEX]
    var tris := idx.size() / 3

    # Triangle soup: ConcavePolygonShape3D.set_faces wants 3 verts per triangle.
    var faces := PackedVector3Array()
    faces.resize(idx.size())
    for i in idx.size():
        faces[i] = verts[idx[i]]

    var best := 1e30
    var total := 0.0
    for _i in ITERS:
        var shape := ConcavePolygonShape3D.new()
        var t0 := Time.get_ticks_usec()
        shape.set_faces(faces)              # the cook (BVH build) happens here
        var ms := (Time.get_ticks_usec() - t0) / 1000.0
        best = minf(best, ms)
        total += ms
    var avg := total / ITERS
    print("[cook spike] tile %d^3: %d tris -> cook avg %.3f ms, best %.3f ms (n=%d)" % [
        size, tris, avg, best, ITERS])
    assert_gt(tris, 0, "non-empty tile")


func test_cook_cost_16():
    _measure(16)

func test_cook_cost_32():
    _measure(32)

func test_cook_cost_64():
    _measure(64)   # coherent player region size for VISION #2 (covers ~24m aim reach)
