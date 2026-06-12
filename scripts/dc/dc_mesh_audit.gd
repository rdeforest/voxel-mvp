class_name DCMeshAudit

# Scans a DC ArrayMesh surface for bad triangles (the `dcaudit` console command):
#   degen  — zero-area (collapsed) triangle
#   sliver — extreme aspect ratio (a long thin needle)
#   tilted — facet normal far from its vertices' shading normals: a steep facet the
#            grass shader paints as dirt, the visible symptom of a bad LOD vertex.
# Reports world coords (mesh-local + the surface origin) so a live anomaly can be
# located exactly. Pure observer: it reads the arrays it's handed and prints — it
# never re-meshes, since a rebuild could mask the stale-mesh artifact being chased.

const _DEGEN_AREA    := 1e-3    # m² below this is a collapsed triangle
const _SLIVER_ASPECT := 80.0    # longest-edge² / area above this is a needle
const _TILT_DEG      := 35.0    # facet-vs-shading-normal deviation that reads as a steep facet
const _MAX_REPORTED  := 15      # cap the per-run print so a bad mesh doesn't flood the log


static func report(arrays: Array, origin: Vector3i) -> void:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var o := Vector3(origin)
    var bad: Array = []
    for i in range(0, idx.size(), 3):
        var a := verts[idx[i]]; var b := verts[idx[i + 1]]; var c := verts[idx[i + 2]]
        var cross := (b - a).cross(c - a)
        var area := cross.length() * 0.5
        var le: float = maxf(maxf((b - a).length(), (c - b).length()), (a - c).length())
        var aspect := le * le / maxf(area, 1e-9)
        var dev := 0.0
        if area > 1e-6:
            var vn := (norms[idx[i]] + norms[idx[i + 1]] + norms[idx[i + 2]])
            if vn.length() > 1e-6:
                dev = rad_to_deg(acos(clampf(absf(cross.normalized().dot(vn.normalized())), 0.0, 1.0)))
        var degenerate := area < _DEGEN_AREA
        var sliver := aspect > _SLIVER_ASPECT
        var tilted := dev > _TILT_DEG and area >= _DEGEN_AREA
        if degenerate or sliver or tilted:
            bad.append({"w": (a + b + c) / 3.0 + o, "area": area, "aspect": aspect, "dev": dev,
                "tag": ("degen" if degenerate else "sliver" if sliver else "tilted")})
    bad.sort_custom(func(x, y): return _severity(x) > _severity(y))
    print("dcaudit: %d suspect triangles of %d (origin %s)" % [bad.size(), _triangle_count(idx.size()), str(origin)])
    for i in mini(_MAX_REPORTED, bad.size()):
        var t = bad[i]
        print("  [%s] world=%s  area=%.4f aspect=%.1f facet_vs_normals=%.1f deg" % [
            t["tag"], str(t["w"]), t["area"], t["aspect"], t["dev"]])


# Rank slivers above tilts above the rest, then by tilt severity — worst first.
static func _severity(t: Dictionary) -> float:
    return t["dev"] + (200.0 if t["aspect"] > _SLIVER_ASPECT else 0.0)


static func _triangle_count(index_size: int) -> int:
    @warning_ignore("integer_division")
    return index_size / 3
