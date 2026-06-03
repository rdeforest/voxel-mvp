class_name DualContour
extends RefCounted

# Bite A of the DC-QEF transition (see docs/roadmap/implementation/14): a plain
# Dual Contouring mesher over a UNIFORM grid. Field in, ArrayMesh out. No octree,
# no LOD. The field source is pluggable (SdfField): SdfAnalytic for an analytic
# SDF, SdfBaked for pre-sampled grid data. Validated against analytic SDFs.
#
# DC places exactly one vertex per cell, positioned anywhere inside the cell by
# the QEF (QefSolver) so the surface can sit off-grid. Each grid edge that
# changes sign is shared by four cells; their vertices join into a quad.

# Cube corners indexed by xyz bits: 0=(0,0,0) .. 7=(1,1,1).
# The 12 edges as corner-index pairs.
const CELL_EDGES := [
    [0, 1], [2, 3], [4, 5], [6, 7],   # along x
    [0, 2], [1, 3], [4, 6], [5, 7],   # along y
    [0, 4], [1, 5], [2, 6], [3, 7],   # along z
]

# Ring of the four cells around a grid edge, as (perp-u, perp-v) offsets.
const CELL_RING := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(-1, 0)]


# Convenience: mesh an analytic SDF callable (wrapped as SdfAnalytic).
static func build_mesh(sdf: Callable, res: Vector3i, origin := Vector3.ZERO, cell := 1.0) -> ArrayMesh:
    return build_field(SdfAnalytic.new(sdf), res, origin, cell)

# field: pluggable source. res: cells per axis. Corners at origin + corner * cell.
static func build_field(field: SdfField, res: Vector3i, origin := Vector3.ZERO, cell := 1.0) -> ArrayMesh:
    var samples := _sample_field(field, res, origin, cell)

    var cell_vertex := {}                     # Vector3i cell -> vertex index
    var verts       := PackedVector3Array()
    var normals     := PackedVector3Array()
    _build_vertices(field, samples, res, origin, cell, cell_vertex, verts, normals)

    var indices := PackedInt32Array()
    _build_quads(field, samples, res, origin, cell, cell_vertex, verts, indices)

    if verts.is_empty():
        return ArrayMesh.new()

    # Crease-aware normals: smooth where the surface is smooth (the field's
    # gradient normals), hard where it creases (split vertices). See MeshNormals.
    var finalized := MeshNormals.with_crease_normals(verts, indices, normals)
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = finalized["verts"]
    arrays[Mesh.ARRAY_NORMAL] = finalized["normals"]
    arrays[Mesh.ARRAY_INDEX]  = finalized["indices"]

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


# --- field sampling ---

static func _sample_field(field: SdfField, res: Vector3i, origin: Vector3, cell: float) -> Dictionary:
    var samples := {}
    for z in res.z + 1:
        for y in res.y + 1:
            for x in res.x + 1:
                var corner := Vector3i(x, y, z)
                samples[corner] = field.value(origin + Vector3(corner) * cell)
    return samples

static func _corner_offset(i: int) -> Vector3i:
    return Vector3i(i & 1, (i >> 1) & 1, (i >> 2) & 1)


# --- one vertex per surface cell ---

static func _build_vertices(
        field: SdfField, samples: Dictionary, res: Vector3i, origin: Vector3, cell: float,
        cell_vertex: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array) -> void:
    for cz in res.z:
        for cy in res.y:
            for cx in res.x:
                var c := Vector3i(cx, cy, cz)
                var qef := QefSolver.new()
                var nsum := Vector3.ZERO
                for edge in CELL_EDGES:
                    var ca: Vector3i = c + _corner_offset(edge[0])
                    var cb: Vector3i = c + _corner_offset(edge[1])
                    var fa: float = samples[ca]
                    var fb: float = samples[cb]
                    if (fa < 0.0) == (fb < 0.0):
                        continue
                    if fa == fb:
                        continue
                    var t := fa / (fa - fb)
                    var pa := origin + Vector3(ca) * cell
                    var pb := origin + Vector3(cb) * cell
                    var p := pa.lerp(pb, t)
                    var n := field.gradient(p)
                    qef.add_plane(p, n)
                    nsum += n
                if qef.count() == 0:
                    continue
                var cmin := origin + Vector3(c) * cell
                var cmax := cmin + Vector3.ONE * cell
                cell_vertex[c] = verts.size()
                verts.append(qef.solve(cmin, cmax))
                normals.append(nsum.normalized())


# --- quads across sign-changing grid edges ---

static func _build_quads(
        field: SdfField, samples: Dictionary, res: Vector3i, origin: Vector3, cell: float,
        cell_vertex: Dictionary, verts: PackedVector3Array, indices: PackedInt32Array) -> void:
    var res_arr := [res.x, res.y, res.z]
    for axis in 3:
        var u := (axis + 1) % 3
        var w := (axis + 2) % 3
        var ga := [0, 0, 0]
        for a in res_arr[axis]:
            ga[axis] = a
            for uu in range(1, res_arr[u]):
                ga[u] = uu
                for ww in range(1, res_arr[w]):
                    ga[w] = ww
                    _try_quad(field, samples, axis, u, w, ga, origin, cell, cell_vertex, verts, indices)

static func _try_quad(
        field: SdfField, samples: Dictionary, axis: int, u: int, w: int, ga: Array,
        origin: Vector3, cell: float,
        cell_vertex: Dictionary, verts: PackedVector3Array, indices: PackedInt32Array) -> void:
    var g  := Vector3i(ga[0], ga[1], ga[2])
    var gb := g
    gb[axis] += 1
    var fa: float = samples[g]
    var fb: float = samples[gb]
    if (fa < 0.0) == (fb < 0.0):
        return

    var ring: Array[int] = []
    for off in CELL_RING:
        var c := [ga[0], ga[1], ga[2]]
        c[u] += off.x
        c[w] += off.y
        var key := Vector3i(c[0], c[1], c[2])
        if not cell_vertex.has(key):
            return   # incomplete ring (shouldn't happen for a clean field); skip
        ring.append(cell_vertex[key])

    # Outward = field gradient at the edge crossing.
    var t := fa / (fa - fb) if fa != fb else 0.5
    var pa := origin + Vector3(g) * cell
    var pb := origin + Vector3(gb) * cell
    var outward := field.gradient(pa.lerp(pb, t))

    _emit_quad(ring, verts, outward, indices)

# Two triangles for the ring [0,1,2,3]; flip winding so the face normal agrees
# with `outward` (field gradient), making the surface face air regardless of the
# ring's traversal direction.
static func _emit_quad(ring: Array, verts: PackedVector3Array, outward: Vector3, indices: PackedInt32Array) -> void:
    var p0 := verts[ring[0]]
    var p1 := verts[ring[1]]
    var p2 := verts[ring[2]]
    # Godot treats clockwise-from-the-front triangles as front faces. The right-
    # hand normal of [0,1,2] is (p1-p0)x(p2-p0); when it points OUTWARD the ring
    # reads counter-clockwise from outside (a Godot back face), so reverse it.
    var rh_outward := (p1 - p0).cross(p2 - p0).dot(outward) >= 0.0
    if rh_outward:
        indices.append_array([ring[0], ring[2], ring[1], ring[0], ring[3], ring[2]])
    else:
        indices.append_array([ring[0], ring[1], ring[2], ring[0], ring[2], ring[3]])
