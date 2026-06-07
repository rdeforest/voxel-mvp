class_name VoxelOctree
extends RefCounted

# The data substrate (Phase B): a SPARSE, ADAPTIVE octree that stores an edited SDF
# field (+ material) at whatever resolution each region needs — down to sub-metre,
# which godot_voxel's fixed 1 m grid can't represent. Surface-dominated: a node only
# subdivides where an imprint's surface passes through it, so storage scales with
# surface AREA, not volume (the manifesto's "1.5 TB, not an exabyte" thesis — store
# the skin, not the rock).
#
# Each leaf holds the field sampled at its 8 corners (so Dual Contouring reads a smooth
# trilinear field + clean edge crossings, same as it does from a dense grid) plus one
# material id. A region with no leaf is "unwritten" — the caller falls back to the
# procedural generator there, exactly like godot_voxel's generator + sparse edits, but
# adaptive.
#
# Prototype in GDScript to prove the representation; port to C++ (worker-thread read)
# once it's meshing edits end-to-end. One node = one VoxelOctree (recursive).

const EMPTY := INF   # sample() of an unwritten region; caller uses the generator instead

enum Op { UNION, SUBTRACT }   # add solid / carve solid away

# Corner offsets indexed by xyz bits (matches the DC mesher's CORNER table).
const CORNERS: Array[Vector3] = [
    Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
    Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1),
]

var origin:   Vector3
var size:     float
var children: Array[VoxelOctree] = []   # 8 when internal; empty when leaf-or-unwritten
var corners:  PackedFloat32Array        # 8 corner SDF values; empty = unwritten
var material: int = 0
var vertex:   int = -1                  # mesh-vertex index (set by OctreeMesher)


func _init(p_origin := Vector3.ZERO, p_size := 1.0) -> void:
    origin = p_origin
    size   = p_size


# Imprint `field` (world point -> signed distance, negative inside) into the tree,
# refining to leaves of side `min_leaf` wherever the field's surface passes. Returns
# true if anything was written under this node. `material` tags the written leaves.
# `mat` is either an int (one material everywhere) or a Callable(Vector3)->int (per-point
# material, used by stamp() to keep existing terrain's material where it doesn't add).
func imprint(field: Callable, min_leaf: float, mat = 0) -> void:
    var center := origin + Vector3.ONE * (size * 0.5)
    var fc: float = field.call(center)
    if absf(fc) > size * 0.8660254:
        # Surface beyond the node's circumradius -> no detail here; one UNIFORM leaf
        # carrying the sign (solid/air) for the whole node. Storage = O(1) for bulk.
        _write_uniform(fc, _mat_at(mat, center))
        return
    if size <= min_leaf * 1.0000001:
        _write_leaf(field, _mat_at(mat, center))   # at the skin -> fine leaf with corner samples
        return
    _subdivide()
    for ch in children:
        ch.imprint(field, min_leaf, mat)

func _mat_at(mat, p: Vector3) -> int:
    return mat.call(p) if mat is Callable else mat


# Stamp a shape (world point -> signed distance) into the EXISTING field, combining by
# `op`: UNION = min(existing, shape) (add solid), SUBTRACT = max(existing, -shape) (carve).
# This is "imprinting" (doc 03 §4) — terrain and parts are one field, edited the same way.
# IN PLACE: existing leaves keep their exact corners (just combined with the brush), and a
# coarse leaf is only subdivided where the brush's surface needs finer detail, inheriting
# the parent field on the way down. So surface the brush doesn't reach is untouched — no
# re-sampling, no cracks.
func stamp(shape: Callable, min_leaf: float, p_material: int, op: Op) -> void:
    if not children.is_empty():
        for ch in children:
            ch.stamp(shape, min_leaf, p_material, op)
        return
    if corners.is_empty():
        return   # unwritten region — the brush only edits existing matter (prototype)
    var center := origin + Vector3.ONE * (size * 0.5)
    var sc: float = shape.call(center)
    # Brush surface passes through this leaf at a finer scale than it -> refine, inheriting
    # this leaf's field into the children, then recurse.
    if size > min_leaf * 1.0000001 and absf(sc) <= size * 0.8660254:
        _subdivide_inherit()
        for ch in children:
            ch.stamp(shape, min_leaf, p_material, op)
        return
    # Apply the combine at this leaf's corners.
    var binds := op == Op.UNION and sc < _trilerp(0.5, 0.5, 0.5)
    for i in 8:
        var s: float = shape.call(origin + CORNERS[i] * size)
        corners[i] = minf(corners[i], s) if op == Op.UNION else maxf(corners[i], -s)
    if binds:
        material = p_material   # this leaf is now solid because the stamp added it


# Subdivide a leaf into 8 children that reproduce its field (corners trilerp'd from this
# leaf), so refining for a brush doesn't change the existing surface.
func _subdivide_inherit() -> void:
    var half := size * 0.5
    var src := corners
    children = []
    for c in CORNERS:
        var child := VoxelOctree.new(origin + c * half, half)
        child.material = material
        child.corners = PackedFloat32Array()
        for cc in CORNERS:
            var f := (c + cc) * 0.5   # child corner as a fraction of this leaf
            child.corners.append(_trilerp_of(src, f.x, f.y, f.z))
        children.append(child)
    corners = PackedFloat32Array()


static func _trilerp_of(c: PackedFloat32Array, fx: float, fy: float, fz: float) -> float:
    var c00 := lerpf(c[0], c[1], fx)
    var c10 := lerpf(c[2], c[3], fx)
    var c01 := lerpf(c[4], c[5], fx)
    var c11 := lerpf(c[6], c[7], fx)
    return lerpf(lerpf(c00, c10, fy), lerpf(c01, c11, fy), fz)


# Signed distance at world point `p`: trilinear within the finest written leaf, or
# EMPTY if `p` is in an unwritten region.
func sample(p: Vector3) -> float:
    if not children.is_empty():
        return children[_child_index(p)].sample(p)
    if corners.is_empty():
        return EMPTY
    var f := (p - origin) / size
    return _trilerp(f.x, f.y, f.z)


# Material id at `p` (0 / unwritten-default in empty regions).
func material_at(p: Vector3) -> int:
    if not children.is_empty():
        return children[_child_index(p)].material_at(p)
    return material


# Count of written leaves — the storage measure (should track surface area, not volume).
func leaf_count() -> int:
    if not children.is_empty():
        var n := 0
        for ch in children:
            n += ch.leaf_count()
        return n
    return 0 if corners.is_empty() else 1


# The written leaf containing world point `p`, or null if `p` is outside / unwritten.
func find_leaf(p: Vector3) -> VoxelOctree:
    if p.x < origin.x or p.y < origin.y or p.z < origin.z:
        return null
    if p.x >= origin.x + size or p.y >= origin.y + size or p.z >= origin.z + size:
        return null
    if not children.is_empty():
        return children[_child_index(p)].find_leaf(p)
    return self if not corners.is_empty() else null


# Append every written leaf (fine surface leaves and bulk uniform leaves) to `out`.
func collect_leaves(out: Array) -> void:
    if not children.is_empty():
        for ch in children:
            ch.collect_leaves(out)
    elif not corners.is_empty():
        out.append(self)


# --- Internals ---

func _subdivide() -> void:
    var half := size * 0.5
    children = []
    for c in CORNERS:
        children.append(VoxelOctree.new(origin + c * half, half))

func _write_leaf(field: Callable, p_material: int) -> void:
    corners = PackedFloat32Array()
    for c in CORNERS:
        corners.append(field.call(origin + c * size))
    material = p_material

# A bulk node far from any surface: all 8 corners share one value, so trilinear
# sampling returns that sign everywhere inside. One leaf for a whole solid/air region.
func _write_uniform(value: float, p_material: int) -> void:
    corners = PackedFloat32Array([value, value, value, value, value, value, value, value])
    material = p_material if value < 0.0 else 0   # material only meaningful for solid

func _child_index(p: Vector3) -> int:
    var mid := origin + Vector3.ONE * (size * 0.5)
    return (1 if p.x >= mid.x else 0) | (2 if p.y >= mid.y else 0) | (4 if p.z >= mid.z else 0)

func _trilerp(fx: float, fy: float, fz: float) -> float:
    var c00 := lerpf(corners[0], corners[1], fx)
    var c10 := lerpf(corners[2], corners[3], fx)
    var c01 := lerpf(corners[4], corners[5], fx)
    var c11 := lerpf(corners[6], corners[7], fx)
    return lerpf(lerpf(c00, c10, fy), lerpf(c01, c11, fy), fz)
