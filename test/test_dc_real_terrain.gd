extends GutTest

# Meshes a region of the ACTUAL terrain generator (VoxelGeneratorNoise2D, matching
# world.tscn) with the production C++ DCOctreeMesher and asserts the surface has no
# interior cracks. This guards mesher changes against the failure the analytic
# sphere can't show: the terrain SDF is a 2D heightmap, so it's unit-distance
# vertically but OVERESTIMATES true distance on slopes — which shattered a
# magnitude-based surface-adaptive refine on mountainsides (see
# dc-sdf-not-unit-distance). The sphere is exact-distance and hid it.
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


# The production mesher must produce a sound (crack-free) surface on real terrain.
# Fed as a single clipmap level (origin 0, cell 1, half0 huge) so target_cell_size
# is 1 everywhere — uniform full subdivision over the region.
func test_cpp_mesher_sound_on_real_terrain():
    var data := _bake_data()
    var arrays := DCOctreeMesher.new().mesh_clipmap(
            [data], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
            Vector3.ZERO, 1e9, DEPTH)
    assert_false(arrays.is_empty(), "C++ mesher produced arrays")
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    assert_gt(verts.size(), 200, "meaningfully tessellated")
    var audit := _crack_audit(verts, idx)
    assert_eq(audit["nonmanifold"], 0, "non-manifold edges")
    assert_eq(audit["interior"], 0, "interior boundary edges (cracks)")


func _bake_lod(origin: Vector3i, lod: int) -> PackedFloat32Array:
    var buf := VoxelBuffer.new()
    buf.create(DIM, DIM, DIM)
    _generator().generate_block(buf, Vector3(origin), lod)
    var data := PackedFloat32Array()
    data.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                data[i] = buf.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
                i += 1
    return data


# Two-level clipmap on real terrain. The coarse LOD-1 mip drops high-frequency detail
# the fine LOD-0 level has, so the two surfaces sit at different heights at the level
# boundary. A hard level switch stepped the surface there and the crack-free stitch
# bridged the step with near-vertical slivers — thin tilted triangles the grass shader
# painted as dirt (the dark-flap artifact). Geomorph (Clipmap::value blends the levels
# continuously across the band) removes the step. Guard: no surface-tilted high-aspect
# triangles straddling the boundary.
func test_no_lod_boundary_slivers():
    var center := Vector3(16, 16, 16)        # surface ~lattice y 16; boundary shell at cheb 8
    var arrays := DCOctreeMesher.new().mesh_clipmap(
            [_bake_lod(WORLD_ORIGIN, 0), _bake_lod(WORLD_ORIGIN + Vector3i(-16, -16, -16), 1)], DIM,
            PackedVector3Array([Vector3.ZERO, Vector3(-16, -16, -16)]),
            PackedFloat32Array([1.0, 2.0]), center, 8.0, DEPTH)
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var boundary_slivers := 0
    for i in range(0, idx.size(), 3):
        var a := verts[idx[i]]; var b := verts[idx[i + 1]]; var c := verts[idx[i + 2]]
        var cross := (b - a).cross(c - a)
        var area := cross.length() * 0.5
        if area < 1e-3:
            continue                          # zero-area degenerates are invisible, separate issue
        var le: float = maxf(maxf((b - a).length(), (c - b).length()), (a - c).length())
        var vn := norms[idx[i]] + norms[idx[i + 1]] + norms[idx[i + 2]]
        var dev := 0.0
        if vn.length() > 1e-6:
            dev = rad_to_deg(acos(clampf(absf(cross.normalized().dot(vn.normalized())), 0.0, 1.0)))
        if le * le / area > 80.0 or dev > 35.0:
            var ctr := (a + b + c) / 3.0
            var cheb: float = maxf(maxf(absf(ctr.x - center.x), absf(ctr.y - center.y)), absf(ctr.z - center.z))
            if absf(cheb - 8.0) < 1.5:
                boundary_slivers += 1
    assert_lte(boundary_slivers, 1, "near-vertical slivers straddling the LOD boundary (geomorph regression)")
