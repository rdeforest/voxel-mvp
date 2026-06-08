extends GutTest

# The procedural terrain is a VoxelGeneratorGraph (assets/generators/terrain.tres): a 3D
# density field of mountains, no caves. This proves the whole chain — graph field -> bulk
# generate_block -> production DCOctreeMesher — has the right sign convention, is SOLID all
# the way down (physics-stable), and meshes a sound surface. Terrain material (rock/grass)
# is shader-side (terrain.gdshader, by altitude+slope), so it isn't tested here.
# Built by tools/build_terrain_graph.gd; re-run that if you change the graph in code.

const GRAPH := "res://assets/generators/terrain.tres"
const SIZE  := 64                          # depth-6 octree root (2^6)
const DIM   := SIZE + 1
const DEPTH := 6
const WALL_EPS := 2.0

# Found from the actual (user-tunable) generator so the test region straddles the surface
# wherever the terrain is tuned to, instead of a hard-coded band that breaks when you change
# period/amplitude. Set in before_all.
var ORIGIN := Vector3i(-32, 18, -32)


func _gen() -> VoxelGenerator:
    return load(GRAPH) as VoxelGenerator


func before_all() -> void:
    # Scan a tall thin column at world (0,0) for the surface (first solid below air,
    # top-down), then centre the SIZE^3 test cube vertically on it.
    var h := 512
    var y0 := -192
    var buf := VoxelBuffer.new()
    buf.create(4, h, 4)
    _gen().generate_block(buf, Vector3i(-2, y0, -2), 0)
    var ch := VoxelBuffer.CHANNEL_SDF
    var surf := y0 + h / 2
    for y in range(h - 2, 0, -1):
        if buf.get_voxel_f(2, y, 2, ch) < 0.0 and buf.get_voxel_f(2, y + 1, 2, ch) >= 0.0:
            surf = y0 + y
            break
    ORIGIN = Vector3i(-32, surf - SIZE / 2, -32)
    gut.p("terrain graph: surface ~y=%d, test cube origin=%s" % [surf, str(ORIGIN)])


func _bake() -> PackedFloat32Array:
    var buf := VoxelBuffer.new()
    buf.create(DIM, DIM, DIM)
    _gen().generate_block(buf, Vector3(ORIGIN), 0)
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


func test_graph_loads_and_compiles() -> void:
    var gen: VoxelGeneratorGraph = load(GRAPH)
    assert_not_null(gen, "terrain graph resource loads")
    assert_true(gen.compile().get("success", false), "graph compiles")


func test_solid_all_the_way_down_no_caves() -> void:
    # For every column that has a surface inside the cube, everything below the surface must
    # be solid — no interior air pockets (caves) that would be physics-unstable. Scans all
    # columns so it doesn't depend on where a peak happens to land.
    var sdf := _bake()
    var columns_with_surface := 0
    var air_pockets := 0
    for z in DIM:
        for x in DIM:
            var surf := -999
            for y in range(DIM - 1, -1, -1):
                var s := sdf[x + DIM * (y + DIM * z)]
                if surf == -999:
                    if s < 0.0:
                        surf = y
                elif s > 0.0:                    # below the surface but air -> a cave
                    air_pockets += 1
            if surf > 1:                          # a genuine surface, not solid-to-the-top
                columns_with_surface += 1
    gut.p("terrain: columns_with_surface=%d  interior_air_pockets=%d" % [columns_with_surface, air_pockets])
    assert_gt(columns_with_surface, 100, "terrain has a real surface across the region")
    assert_eq(air_pockets, 0, "solid all the way down — no caves (physics-stable)")


func test_meshes_a_sound_surface() -> void:
    var data := _bake()
    var arrays := DCOctreeMesher.new().mesh_clipmap(
            [data], DIM, PackedVector3Array([Vector3(ORIGIN)]), PackedFloat32Array([1.0]),
            Vector3(ORIGIN), 1e9, DEPTH)
    assert_false(arrays.is_empty(), "mesher produced arrays")
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var tris := idx.size() / 3
    assert_gt(verts.size(), 200, "meaningfully tessellated terrain")
    var counts := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
            var k := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[k] = counts.get(k, 0) + 1
    var interior := 0
    var nonmanifold := 0
    for k in counts:
        if counts[k] > 2:
            nonmanifold += 1
        elif counts[k] == 1 and not (_on_wall(verts[k.x]) and _on_wall(verts[k.y])):
            interior += 1
    gut.p("graph mesh: tris=%d interior_holes=%d (%.1f%%) nonmanifold=%d" % [
        tris, interior, 100.0 * float(interior) / float(tris), nonmanifold])
    assert_eq(nonmanifold, 0, "mesher stays manifold")
    # Heightfield meshes far cleaner than caves did; sharp ridged ridgelines still hit the
    # documented thin-feature crack limit, so allow a small slice.
    assert_lt(float(interior) / float(tris), 0.05, "surface essentially crack-free")
