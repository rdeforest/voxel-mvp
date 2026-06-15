extends GutTest

# Robert's scenario: a 4x22x4 pillar viewed from directly above (camera over the top),
# meshed with the in-game settings (multi-LOD clipmap + error-driven collapse on). Do we
# get a watertight box, or non-watertight "modern art"? The pillar spans LOD bands (top
# near the camera = LOD0, base far = LOD1/2), which the analytic box-in-LOD0 tests never
# exercised.

const DIM   := 33
const DEPTH := 5
const PILLAR_C := Vector3(16, 16, 16)
const PILLAR_D := Vector3(4, 22, 4)        # 4 wide, 22 tall


var _clamp := 0.0   # 0 = unclamped; else clamp SDF to [-_clamp, _clamp] like stored data

func _box(p: Vector3) -> float:
    var d := CsgSdf.box(p - PILLAR_C, PILLAR_D)
    return clampf(d, -_clamp, _clamp) if _clamp > 0.0 else d

func _level(cell: float) -> PackedFloat32Array:
    var d := PackedFloat32Array()
    d.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                d[i] = _box(Vector3(x, y, z) * cell)
                i += 1
    return d

func _edge_audit(idx: PackedInt32Array) -> Dictionary:
    var counts := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
            var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[key] = counts.get(key, 0) + 1
    var boundary := 0
    var nonmanifold := 0
    for k in counts:
        if counts[k] == 1: boundary += 1
        elif counts[k] > 2: nonmanifold += 1
    return {"boundary": boundary, "nonmanifold": nonmanifold}


func _run(label: String) -> void:
    var cam := Vector3(16, 31, 16)   # directly above the pillar top, looking down
    var arrays := DCOctreeMesher.new().mesh_clipmap(
        [_level(1.0), _level(2.0), _level(4.0)], DIM,
        PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]),
        PackedFloat32Array([1.0, 2.0, 4.0]),
        cam, 16.0, DEPTH, 8.0, true, Vector3i())
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var a := _edge_audit(idx)
    var max_dev := 0.0
    for v in verts:
        max_dev = maxf(max_dev, absf(_box(v)))
    gut.p("%s: verts=%d tris=%d boundary=%d nonmanifold=%d max_dev=%.2f" % [
        label, verts.size(), idx.size() / 3, a["boundary"], a["nonmanifold"], max_dev])

func test_clamp_sweep() -> void:
    for c in [0.0, 5.0, 1.0, 0.3]:
        _clamp = c
        _run("clamp=%.1f" % c)
    assert_true(true)   # diagnostic — read the numbers

func test_pillar_from_above() -> void:
    _clamp = 0.0
    # Camera directly above the pillar top (y=27), looking down — "standing on top".
    var cam := Vector3(16, 31, 16)
    var arrays := DCOctreeMesher.new().mesh_clipmap(
        [_level(1.0), _level(2.0), _level(4.0)], DIM,
        PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]),
        PackedFloat32Array([1.0, 2.0, 4.0]),
        cam, 16.0, DEPTH, 8.0, true, Vector3i())   # error_driven = true
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]

    var a := _edge_audit(idx)
    var max_dev := 0.0
    for v in verts:
        max_dev = maxf(max_dev, absf(_box(v)))
    gut.p("pillar-from-above: verts=%d tris=%d boundary_edges=%d nonmanifold=%d max_dev=%.2f" % [
        verts.size(), idx.size() / 3, a["boundary"], a["nonmanifold"], max_dev])

    assert_eq(a["boundary"], 0, "watertight (no boundary edges / holes)")
    assert_eq(a["nonmanifold"], 0, "manifold (no non-manifold edges)")
    assert_lt(max_dev, 1.5, "vertices stay near the true box")
