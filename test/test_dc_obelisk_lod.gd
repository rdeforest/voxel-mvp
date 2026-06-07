extends GutTest

# Reproduce "the middle of the obelisk is missing." A thin tall column meshed at LOD0
# is complete; meshed through the clipmap with the camera offset so the column's upper
# reach falls in the LOD1/LOD2 bands, the downsampling drops the thin feature there
# (it falls between coarse samples — Nyquist) and a height gap opens. Natural (broad)
# terrain wouldn't do this; only thin edits.

const DIM   := 33
const DEPTH := 5
const COL_XZ := Vector2(14, 14)     # off the coarse grid so it can fall between samples
const COL_R  := 1.5                 # ~3 m wide
const Y0 := 2.0
const Y1 := 30.0


func _col(p: Vector3) -> float:
    var radial := Vector2(p.x, p.z).distance_to(COL_XZ) - COL_R
    var axial := maxf(Y0 - p.y, p.y - Y1)
    return maxf(radial, axial)       # solid inside the column

func _level(cell: float) -> PackedFloat32Array:
    var d := PackedFloat32Array()
    d.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                d[i] = _col(Vector3(x, y, z) * cell)
                i += 1
    return d

# Which 4 m height slices [Y0,Y1] contain at least one column vertex.
func _filled_slices(verts: PackedVector3Array) -> Dictionary:
    var s := {}
    for v in verts:
        if Vector2(v.x, v.z).distance_to(COL_XZ) < COL_R + 1.5:
            s[int((v.y - Y0) / 4.0)] = true
    return s


func test_obelisk_loses_its_middle_in_the_clipmap() -> void:
    # Pure LOD0 over the whole column: complete.
    var pure: PackedVector3Array = DCOctreeMesher.new().mesh_clipmap(
        [_level(1.0)], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        Vector3(COL_XZ.x, 16, COL_XZ.y), 1e9, DEPTH)[Mesh.ARRAY_VERTEX]
    # Clipmap with camera low at the base, so the upper column is in LOD1/LOD2 bands.
    var clip: PackedVector3Array = DCOctreeMesher.new().mesh_clipmap(
        [_level(1.0), _level(2.0), _level(4.0)], DIM,
        PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]),
        PackedFloat32Array([1.0, 2.0, 4.0]),
        Vector3(COL_XZ.x, Y0, COL_XZ.y), 16.0, DEPTH)[Mesh.ARRAY_VERTEX]

    var n_slices := int((Y1 - Y0) / 4.0)
    var pure_s := _filled_slices(pure)
    var clip_s := _filled_slices(clip)
    gut.p("column slices filled — pure LOD0: %d/%d   clipmap: %d/%d" % [
        pure_s.size(), n_slices, clip_s.size(), n_slices])
    assert_almost_eq(pure_s.size(), n_slices, 1, "pure LOD0 meshes the whole column")
    # Documents the bug (expected to FAIL): the clipmap drops slices the thin column
    # falls between at coarse LOD.
    assert_almost_eq(clip_s.size(), n_slices, 1, "clipmap keeps the whole column too")
