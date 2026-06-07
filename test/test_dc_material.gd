extends GutTest

# Stage-2 material pipeline at the C++ boundary:
#   - DCRegionReader.read_indices_lod returns size^3 ids, defaulting to 0 (natural).
#   - DCOctreeMesher.mesh_clipmap, given per-level indices + a palette, emits an
#     ARRAY_COLOR whose rgb is the sampled material colour and whose alpha flags
#     material (0) vs natural (1). Without indices it emits no colour (back-compat).

const DIM    := 33
const DEPTH  := 5
const CENTER := Vector3(16, 16, 16)
const RADIUS := 10.0


func _sphere_level(origin: Vector3, cell: float) -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                data[i] = (origin + Vector3(x, y, z) * cell).distance_to(CENTER) - RADIUS
                i += 1
    return data


func test_read_indices_defaults_to_natural() -> void:
    var t := VoxelLodTerrain.new()
    # 8-bit indices (default 0 = natural), the format world.gd assigns. The default
    # 16-bit format packs indices as 0x3210, which would read back nonzero.
    var fmt := VoxelFormat.new()
    fmt.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_8_BIT)
    t.format = fmt
    add_child_autofree(t)
    var ids := DCRegionReader.new().read_indices_lod(t, 0, Vector3i.ZERO, Vector3i(DIM, DIM, DIM))
    assert_eq(ids.size(), DIM * DIM * DIM, "size^3 ids")
    var nonzero := 0
    for b in ids:
        if b != 0:
            nonzero += 1
    assert_eq(nonzero, 0, "unstamped terrain is all natural (0)")


func test_mesher_emits_material_colour() -> void:
    var data := _sphere_level(Vector3.ZERO, 1.0)
    # Every cell tagged material id 2, so every surface vertex samples id 2.
    var ids := PackedByteArray()
    ids.resize(DIM * DIM * DIM)
    ids.fill(2)
    var known := Color(0.85, 0.75, 0.55, 1.0)
    var palette := PackedColorArray([Color(0, 0, 0, 1), Color(1, 0, 0, 1), known])

    var arrays := DCOctreeMesher.new().mesh_clipmap(
        [data], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        CENTER, 1e9, DEPTH, Vector3(), 0.0, 0.0, false, Vector3i(), [ids], palette)

    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var cols:  PackedColorArray   = arrays[Mesh.ARRAY_COLOR]
    assert_gt(verts.size(), 200, "tessellated")
    assert_eq(cols.size(), verts.size(), "one colour per vertex")
    var c: Color = cols[0]
    assert_almost_eq(c.r, known.r, 0.02, "rgb is the material colour")
    assert_almost_eq(c.g, known.g, 0.02)
    assert_almost_eq(c.b, known.b, 0.02)
    assert_lt(c.a, 0.5, "alpha flags an explicit material")


func test_mesher_without_indices_emits_no_colour() -> void:
    var data := _sphere_level(Vector3.ZERO, 1.0)
    var arrays := DCOctreeMesher.new().mesh_clipmap(
        [data], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]), CENTER, 1e9, DEPTH)
    var cols = arrays[Mesh.ARRAY_COLOR]
    assert_null(cols, "no palette/indices -> no ARRAY_COLOR (godot_voxel meshes stay slope-shaded)")
