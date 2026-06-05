extends GutTest

# Meshes a region of the ACTUAL terrain generator (VoxelGeneratorNoise2D, matching
# world.tscn) and asserts the surface has no interior cracks. This guards mesher
# changes against the failure the analytic sphere can't show: the terrain SDF is a
# 2D heightmap, so it's unit-distance vertically but OVERESTIMATES true distance on
# slopes — which shattered a magnitude-based surface-adaptive refine on mountain-
# sides (see dc-sdf-not-unit-distance). The sphere is exact-distance and hid it.
#
# The region is a 32m cube positioned so the heightfield exits only through the
# four xz side walls (the legit rim); any boundary edge away from those walls is a
# crack. Baked in grid/lattice coords [0,32] so walls sit at 0 and SIZE.

const SIZE     := 32                    # depth-5 octree, [0,32]^3 lattice
const DIM      := SIZE + 1
const DEPTH    := 5
const WALL_EPS := 2.0
const WORLD_ORIGIN := Vector3i(-16, -16, -16)   # surface ~y=0 here; height stays within the cube


func _generator() -> VoxelGeneratorNoise2D:
    var noise := FastNoiseLite.new()
    noise.seed = 1
    noise.fractal_lacunarity = 1.5
    var gen := VoxelGeneratorNoise2D.new()
    gen.height_range = 100.0
    gen.noise = noise
    return gen

func _bake_data() -> PackedFloat32Array:
    var buf := VoxelBuffer.new()
    buf.create(DIM, DIM, DIM)
    _generator().generate_block(buf, Vector3(WORLD_ORIGIN), 0)
    var data := PackedFloat32Array()
    data.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                data[i] = buf.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
                i += 1
    return data

func _bake() -> SdfBaked:
    return SdfBaked.new(_bake_data(), Vector3.ZERO, 1.0, Vector3i(DIM, DIM, DIM))

func _arrays(mesh: ArrayMesh) -> Array:
    assert_eq(mesh.get_surface_count(), 1, "produced a surface")
    return mesh.surface_get_arrays(0)

func _on_side_wall(v: Vector3) -> bool:
    return absf(v.x) < WALL_EPS or absf(v.x - SIZE) < WALL_EPS \
        or absf(v.z) < WALL_EPS or absf(v.z - SIZE) < WALL_EPS

func _crack_audit(verts: PackedVector3Array, idx: PackedInt32Array) -> Dictionary:
    var counts := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
            var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[key] = counts.get(key, 0) + 1
    var interior := 0
    var nonmanifold := 0
    for k in counts:
        if counts[k] > 2:
            nonmanifold += 1
        elif counts[k] == 1 and not (_on_side_wall(verts[k.x]) and _on_side_wall(verts[k.y])):
            interior += 1
    return {"interior": interior, "nonmanifold": nonmanifold}

func _assert_sound(mesh: ArrayMesh) -> void:
    var arrays := _arrays(mesh)
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array     = arrays[Mesh.ARRAY_INDEX]
    assert_gt(verts.size(), 200, "meaningfully tessellated")
    var audit := _crack_audit(verts, idx)
    assert_eq(audit["nonmanifold"], 0, "non-manifold edges")
    assert_eq(audit["interior"], 0, "interior boundary edges (cracks)")


func _verts(mesh: ArrayMesh) -> int:
    return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

# Baseline: full subdivision of real terrain is sound (confirms the region/harness).
func test_full_subdivision_real_terrain_is_sound():
    _assert_sound(OctreeDC.build_field(_bake(), DEPTH))

# The C++ DCOctreeMesher (the production mesher) must produce a sound surface on
# real terrain and match the GDScript OctreeDC it ports. Fed as a single clipmap
# level (origin 0, cell 1) so target_cell_size is 1 everywhere == GDScript uniform.
func test_cpp_mesher_matches_gdscript_on_real_terrain():
    var data := _bake_data()
    var gd_mesh := OctreeDC.build_field(SdfBaked.new(data, Vector3.ZERO, 1.0, Vector3i(DIM, DIM, DIM)), DEPTH)
    var arrays := DCOctreeMesher.new().mesh_clipmap(
            [data], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
            Vector3.ZERO, 1e9, DEPTH)
    assert_false(arrays.is_empty(), "C++ mesher produced arrays")
    var cpp_mesh := ArrayMesh.new()
    cpp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    _assert_sound(cpp_mesh)
    # Same algorithm + field -> vertex counts should track closely (float vs double
    # sampling can flip a few borderline crossings).
    var gd_v := _verts(gd_mesh)
    var cpp_v := _verts(cpp_mesh)
    assert_almost_eq(float(cpp_v), float(gd_v), float(gd_v) * 0.02 + 4.0, "C++ vert count tracks GDScript")
