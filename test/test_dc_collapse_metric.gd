extends GutTest

# The error-driven collapse metric must keep a THIN feature refined while still
# coarsening flat/curved terrain by distance. Scene: a big flat floor (zero-residual
# planes) with a thin vertical spire rising from it, placed OFF the octree centre so
# pure-floor nodes exist to collapse. A metric that averages residual over plane count
# drowns the spire's few high-residual planes in the floor's zeros and collapses the
# cell over it (the thin-feature flapping bug); the undivided residual does not.

const DIM    := 33
const DEPTH  := 5
const FLOOR_Y := 6.0
const SPIRE_XZ := Vector2(10, 10)    # off the [0,32] octree centre (16) on purpose
const SPIRE_R  := 1.3


func _sdf(p: Vector3) -> float:
    var floor_d := p.y - FLOOR_Y
    var spire_d := CsgSdf.cylinder(p - Vector3(SPIRE_XZ.x, 18, SPIRE_XZ.y), SPIRE_R, 24.0)
    return minf(floor_d, spire_d)


func _level(origin: Vector3, cell: float, sphere := false) -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                var p := origin + Vector3(x, y, z) * cell
                data[i] = (p.distance_to(Vector3(16, 16, 16)) - 10.0) if sphere else _sdf(p)
                i += 1
    return data


func _max_aspect(verts: PackedVector3Array, idx: PackedInt32Array) -> float:
    var worst := 0.0
    for i in range(0, idx.size(), 3):
        var a := verts[idx[i]]; var b := verts[idx[i + 1]]; var c := verts[idx[i + 2]]
        var area := (b - a).cross(c - a).length() * 0.5
        var le: float = maxf(maxf((b - a).length(), (c - b).length()), (a - c).length())
        worst = maxf(worst, le * le / maxf(area, 1e-9))
    return worst


func _spire_verts(verts: PackedVector3Array) -> int:
    var n := 0
    for v in verts:
        if Vector2(v.x, v.z).distance_to(SPIRE_XZ) < SPIRE_R + 1.0 and v.y > 12.0 and v.y < 28.0:
            n += 1
    return n


func _mesh(eps: float, sphere := false) -> Array:
    var data := _level(Vector3.ZERO, 1.0, sphere)
    return DCOctreeMesher.new().mesh_clipmap(
        [data], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        Vector3(16, 16, 16), 1e9, DEPTH,
        Vector3(16, 60, 16), 771.0, eps, true, Vector3i())


func test_diagnostic_sweep() -> void:
    gut.p("eps   | spire:tris verts aspect | sphere:tris")
    for eps in [1.0, 4.0, 16.0, 64.0, 256.0, 1024.0]:
        var s := _mesh(eps)
        var sv: PackedVector3Array = s[Mesh.ARRAY_VERTEX]
        var si: PackedInt32Array   = s[Mesh.ARRAY_INDEX]
        var sph := _mesh(eps, true)
        var spi: PackedInt32Array = sph[Mesh.ARRAY_INDEX]
        gut.p("%6.0f | %4d %4d %5.1f | %5d" % [
            eps, si.size() / 3, _spire_verts(sv), _max_aspect(sv, si), spi.size() / 3])
    assert_true(true)


func test_spire_kept_while_terrain_coarsens() -> void:
    # eps=16 aggressively coarsens the sphere; the spire must stay fully meshed with no
    # flapping slivers. (Count-averaged metric: spire lost, aspect ~44.)
    var s := _mesh(16.0)
    var sv: PackedVector3Array = s[Mesh.ARRAY_VERTEX]
    var si: PackedInt32Array   = s[Mesh.ARRAY_INDEX]
    assert_gt(_spire_verts(sv), 150, "thin spire stays fully refined under aggressive collapse")
    assert_lt(_max_aspect(sv, si), 20.0, "no flapping slivers over the spire")

    var sphere_full := (_mesh(16.0, true) as Array)   # err=true already; compare to no-collapse
    var coarse: PackedInt32Array = sphere_full[Mesh.ARRAY_INDEX]
    var full := DCOctreeMesher.new().mesh_clipmap(
        [_level(Vector3.ZERO, 1.0, true)], DIM, PackedVector3Array([Vector3.ZERO]),
        PackedFloat32Array([1.0]), Vector3(16, 16, 16), 1e9, DEPTH,
        Vector3(16, 60, 16), 771.0, 16.0, false, Vector3i())
    var full_idx: PackedInt32Array = full[Mesh.ARRAY_INDEX]
    assert_lt(coarse.size(), full_idx.size() / 2, "curved terrain still coarsens (LOD works)")
