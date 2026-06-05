class_name SdfClipmap
extends SdfField

# A stack of nested baked SDF levels (a clipmap) for distance-graded meshing. All
# levels share a centre (the follow target) in the octree's lattice space; level k
# covers 2^k the extent of level 0 at 2^k the cell size, read from the terrain at
# LOD k so coarse cells sample coarse data — no undersampling holes.
#
# value()/gradient() pick the FINEST level whose box contains the query point, so
# the field is a single-valued function of position. That's what keeps OctreeDC's
# point-location meshing crack-free across level boundaries: two cells sampling the
# same corner get the same value, and boundary cells (corners drawn from two levels)
# bridge the small data-LOD step within one cell rather than leaving a gap.
#
# target_cell_size() reports the cell size the octree should use at a point (= the
# level's LOD cell size). Feeding it to the `refine` predicate makes graded cell
# size and data LOD share the SAME geometry, so they transition together.

var _levels: Array[SdfBaked] = []   # finest (LOD0) first
var _center: Vector3                # shared centre, lattice space
var _half0: float                   # level 0 half-extent (lattice); level k half = _half0 * 2^k


func _init(levels: Array[SdfBaked], center: Vector3, half0: float) -> void:
    _levels = levels
    _center = center
    _half0  = half0


func _level_index(p: Vector3) -> int:
    var d := _chebyshev(p - _center)
    var n := _levels.size()
    for k in n:
        if d <= _half0 * float(1 << k):
            return k
    return n - 1


func value(p: Vector3) -> float:
    return _levels[_level_index(p)].value(p)

func gradient(p: Vector3) -> Vector3:
    return _levels[_level_index(p)].gradient(p)

func target_cell_size(p: Vector3) -> float:
    return float(1 << _level_index(p))


static func _chebyshev(v: Vector3) -> float:
    return maxf(maxf(absf(v.x), absf(v.y)), absf(v.z))
