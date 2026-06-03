class_name MeshNormals
extends RefCounted

# Crease-aware vertex normals for an indexed triangle mesh ("smoothing groups by
# angle"). DC gives one averaged normal per cell vertex, which softens a
# geometrically-sharp edge into a bevel. This regroups each vertex's incident
# faces by angle: faces within the threshold share a smooth normal; a sharper
# crease splits the vertex into separate copies (same position, different normal)
# so the edge shades hard while smooth surfaces stay smooth.
#
# Triangle winding is Godot CW-from-front, so the outward face normal is
# (c-a) x (b-a). `smooth_normals` (optional, e.g. DC's field-gradient normals)
# is used verbatim for vertices that DON'T split, preserving accurate shading on
# smooth surfaces; split clusters use their geometric face-normal average.

const DEFAULT_CREASE_DEG := 40.0


static func with_crease_normals(
        verts: PackedVector3Array,
        indices: PackedInt32Array,
        smooth_normals := PackedVector3Array(),
        threshold_deg := DEFAULT_CREASE_DEG) -> Dictionary:

    var cos_t := cos(deg_to_rad(threshold_deg))
    var tri := indices.size() / 3
    var has_smooth := smooth_normals.size() == verts.size()

    var face_n := PackedVector3Array()
    for t in tri:
        var a := verts[indices[t * 3]]
        var b := verts[indices[t * 3 + 1]]
        var c := verts[indices[t * 3 + 2]]
        var n := (c - a).cross(b - a)   # outward (CW-from-front winding)
        face_n.append(n.normalized() if n.length_squared() > 0.0 else Vector3.UP)

    var incident := {}                  # original vertex -> [triangle indices]
    for t in tri:
        for k in 3:
            var v := indices[t * 3 + k]
            if not incident.has(v):
                incident[v] = []
            incident[v].append(t)

    var out_verts   := PackedVector3Array()
    var out_normals := PackedVector3Array()
    var out_indices := indices.duplicate()

    for v in incident:
        var clusters: Array = []        # each: {sum: Vector3, members: [t]}
        for t in incident[v]:
            var fn: Vector3 = face_n[t]
            var joined := -1
            for ci in clusters.size():
                if (clusters[ci]["sum"] as Vector3).normalized().dot(fn) >= cos_t:
                    joined = ci
                    break
            if joined < 0:
                clusters.append({"sum": fn, "members": [t]})
            else:
                clusters[joined]["sum"] = (clusters[joined]["sum"] as Vector3) + fn
                clusters[joined]["members"].append(t)

        var single := clusters.size() == 1
        for cl in clusters:
            var nidx := out_verts.size()
            out_verts.append(verts[v])
            if single and has_smooth:
                out_normals.append(smooth_normals[v])
            else:
                out_normals.append((cl["sum"] as Vector3).normalized())
            for t in cl["members"]:
                for k in 3:
                    if indices[t * 3 + k] == v:
                        out_indices[t * 3 + k] = nidx

    return {"verts": out_verts, "normals": out_normals, "indices": out_indices}
