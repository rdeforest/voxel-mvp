class_name OctreeDC
extends RefCounted

# Bite D: adaptive-octree Dual Contouring. Instead of the canonical recursive
# face/edge-proc traversal (fiddly index tables), this meshes by MINIMAL-EDGE
# enumeration with octree point-location:
#
#   For each surface leaf's edge that crosses the field, find the (up to four)
#   leaves surrounding that edge by point-querying the octree, dedup their
#   vertices, and emit a quad. When a coarser neighbour is returned twice the
#   dedup collapses the quad to a triangle that fans to the single coarse
#   vertex — which is exactly what stitches a level transition with no crack.
#
# Leaves carry one QEF vertex each (QefSolver); only leaves the surface actually
# crosses get a vertex. Subdivision is driven by the `refine` predicate
# (default: subdivide to max depth, i.e. a uniform grid). Distance-based
# adaptive refinement (cell size graded by distance to the surface) plus the
# octree-balancing pass it needs are a follow-up.
#
# Assumes a balanced/restricted octree (adjacent leaves differ by <= 1 level),
# which the meshing relies on for crack-free seams.

const RING := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
const QUERY_EPS := 0.25   # perpendicular offset to land just across an edge (< half the finest cell)


class Cell:
    extends RefCounted
    var origin:   Vector3i        # lattice coords, multiple of size
    var size:     int             # power of two, lattice units
    var children: Array = []      # 8 Cells, or empty for a leaf
    var vertex:   int = -1        # index into the output vertex array, -1 if no surface

    func _init(p_origin: Vector3i, p_size: int) -> void:
        origin = p_origin
        size   = p_size

    func is_leaf() -> bool:
        return children.is_empty()

    func center() -> Vector3:
        return Vector3(origin) + Vector3.ONE * (size * 0.5)


var _sdf:   Callable
var _root:  Cell
var _field: Dictionary = {}
var _verts:   PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _indices: PackedInt32Array   = PackedInt32Array()


# sdf: Callable(Vector3)->float. The meshed region is the cube [0, 2^depth]^3 in
# world units (the SDF positions its shape within that). refine(center, size,
# depth)->bool gates subdivision beyond the straddle+depth rule (default: always).
static func build_mesh(sdf: Callable, depth: int, refine := Callable()) -> ArrayMesh:
    return OctreeDC.new()._run(sdf, depth, refine)


func _run(sdf: Callable, depth: int, refine: Callable) -> ArrayMesh:
    _sdf  = sdf
    _root = Cell.new(Vector3i.ZERO, 1 << depth)
    _subdivide(_root, depth, refine)

    var leaves: Array = []
    _collect_leaves(_root, leaves)
    for leaf in leaves:
        _build_vertex(leaf)
    for leaf in leaves:
        if leaf.vertex >= 0:
            _emit_leaf_edges(leaf)

    if _verts.is_empty():
        return ArrayMesh.new()
    var finalized := MeshNormals.with_crease_normals(_verts, _indices, _normals)
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = finalized["verts"]
    arrays[Mesh.ARRAY_NORMAL] = finalized["normals"]
    arrays[Mesh.ARRAY_INDEX]  = finalized["indices"]
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


# --- octree build ---

func _sample(lattice: Vector3i) -> float:
    if _field.has(lattice):
        return _field[lattice]
    var v := float(_sdf.call(Vector3(lattice)))
    if v == 0.0:
        v = DualContour.SURFACE_NUDGE
    _field[lattice] = v
    return v

func _subdivide(cell: Cell, max_depth: int, refine: Callable) -> void:
    var depth := _depth_of(cell)
    if depth >= max_depth or cell.size <= 1:
        return
    if refine.is_valid() and not bool(refine.call(cell.center(), float(cell.size), depth)):
        return
    var half := cell.size >> 1
    for i in 8:
        var child := Cell.new(cell.origin + DualContour._corner_offset(i) * half, half)
        cell.children.append(child)
        _subdivide(child, max_depth, refine)

func _depth_of(cell: Cell) -> int:
    # depth = log2(root.size / cell.size)
    var d := 0
    var s := _root.size
    while s > cell.size:
        s >>= 1
        d += 1
    return d

func _collect_leaves(cell: Cell, out: Array) -> void:
    if cell.is_leaf():
        out.append(cell)
        return
    for c in cell.children:
        _collect_leaves(c, out)


# --- per-leaf QEF vertex ---

func _build_vertex(leaf: Cell) -> void:
    var qef := QefSolver.new()
    var nsum := Vector3.ZERO
    for edge in DualContour.CELL_EDGES:
        var ca: Vector3i = leaf.origin + DualContour._corner_offset(edge[0]) * leaf.size
        var cb: Vector3i = leaf.origin + DualContour._corner_offset(edge[1]) * leaf.size
        var fa := _sample(ca)
        var fb := _sample(cb)
        if (fa < 0.0) == (fb < 0.0) or fa == fb:
            continue
        var t := fa / (fa - fb)
        var p := Vector3(ca).lerp(Vector3(cb), t)
        var n := DualContour._gradient(_sdf, p)
        qef.add_plane(p, n)
        nsum += n
    if qef.count() == 0:
        return
    var cmin := Vector3(leaf.origin)
    var cmax := cmin + Vector3.ONE * leaf.size
    leaf.vertex = _verts.size()
    _verts.append(qef.solve(cmin, cmax))
    _normals.append(nsum.normalized())


# --- minimal-edge meshing ---

func _emit_leaf_edges(leaf: Cell) -> void:
    for axis in 3:
        var u := (axis + 1) % 3
        var w := (axis + 2) % 3
        # the leaf's four edges parallel to `axis`
        for su in [0, 1]:
            for sw in [0, 1]:
                _try_edge(leaf, axis, u, w, su, sw)

func _try_edge(leaf: Cell, axis: int, u: int, w: int, su: int, sw: int) -> void:
    # Edge endpoints (lattice) of this leaf, parallel to `axis`.
    var lo := leaf.origin
    lo[u] += su * leaf.size
    lo[w] += sw * leaf.size
    var hi := lo
    hi[axis] += leaf.size
    var fa := _sample(lo)
    var fb := _sample(hi)
    if (fa < 0.0) == (fb < 0.0) or fa == fb:
        return

    # World midpoint and the four cells around the edge (perpendicular quadrants).
    var mid := (Vector3(lo) + Vector3(hi)) * 0.5
    var udir := _axis_vec(u)
    var wdir := _axis_vec(w)
    var cells: Array = []
    for off in RING:
        cells.append(_find_leaf(mid + udir * (off.x * QUERY_EPS) + wdir * (off.y * QUERY_EPS)))

    if not _owns_edge(leaf, cells):
        return

    var ring: Array[int] = []
    for c in cells:
        if c == null or c.vertex < 0:
            return
        if ring.is_empty() or ring[-1] != c.vertex:
            ring.append(c.vertex)
    if ring.size() > 1 and ring[0] == ring[-1]:
        ring.pop_back()
    if ring.size() < 3:
        return

    var t := fa / (fa - fb)
    var outward := DualContour._gradient(_sdf, Vector3(lo).lerp(Vector3(hi), t))
    _emit_poly(ring, outward)

# This leaf owns the edge iff it is a smallest cell around it and, among equal
# smallest cells, the one with the lexicographically least origin. Guarantees
# exactly one of the surrounding cells emits the edge.
func _owns_edge(leaf: Cell, cells: Array) -> bool:
    var min_size := leaf.size
    for c in cells:
        if c != null and c.size < min_size:
            min_size = c.size
    if leaf.size != min_size:
        return false
    for c in cells:
        if c != null and c.size == min_size and _origin_less(c.origin, leaf.origin):
            return false
    return true

static func _origin_less(a: Vector3i, b: Vector3i) -> bool:
    if a.x != b.x: return a.x < b.x
    if a.y != b.y: return a.y < b.y
    return a.z < b.z

func _find_leaf(p: Vector3) -> Cell:
    if p.x < 0.0 or p.y < 0.0 or p.z < 0.0:
        return null
    if p.x >= _root.size or p.y >= _root.size or p.z >= _root.size:
        return null
    var cell := _root
    while not cell.is_leaf():
        var c := cell.center()
        var i := (1 if p.x >= c.x else 0) | (2 if p.y >= c.y else 0) | (4 if p.z >= c.z else 0)
        cell = cell.children[i]
    return cell

static func _axis_vec(axis: int) -> Vector3:
    return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis]

func _emit_poly(ring: Array, outward: Vector3) -> void:
    var p0 := _verts[ring[0]]
    var p1 := _verts[ring[1]]
    var p2 := _verts[ring[2]]
    # Godot CW-from-front: reverse when the right-hand normal points outward.
    var flip := (p1 - p0).cross(p2 - p0).dot(outward) >= 0.0
    if ring.size() == 3:
        if flip: _indices.append_array([ring[0], ring[2], ring[1]])
        else:    _indices.append_array([ring[0], ring[1], ring[2]])
    else:
        if flip: _indices.append_array([ring[0], ring[2], ring[1], ring[0], ring[3], ring[2]])
        else:    _indices.append_array([ring[0], ring[1], ring[2], ring[0], ring[2], ring[3]])
