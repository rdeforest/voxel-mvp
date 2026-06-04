class_name QefSolver
extends RefCounted

# Quadratic Error Function solver for one Dual Contouring cell.
#
# Each crossed cell edge contributes a tangent plane (a point on the surface
# plus its normal). The cell's vertex minimizes the sum of squared distances to
# those planes: E(x) = Σ (n_i · (x - p_i))². On a crease the minimizer lands on
# the intersection of the plane families (recovering the sharp corner); on a
# smooth patch it lands near the average crossing.
#
# Minimizing E means solving the normal equations AᵀA·x = Aᵀb, where each plane
# adds nnᵀ to AᵀA and (n·p)n to Aᵀb. AᵀA is a symmetric 3×3, often rank-
# deficient (flat region → rank 1, straight edge → rank 2). We solve it by
# eigen-decomposition with small eigenvalues clamped to zero (pseudo-inverse),
# biasing the free directions toward the crossings' mass point, then clamp the
# result into the cell so an ill-conditioned solve can't fling the vertex away.

const SINGULAR_REL := 1e-3   # eigenvalues below this fraction of the largest are dropped

# AᵀA (symmetric, 6 unique terms) and Aᵀb, accumulated per plane.
var _a00 := 0.0
var _a01 := 0.0
var _a02 := 0.0
var _a11 := 0.0
var _a12 := 0.0
var _a22 := 0.0
var _atb  := Vector3.ZERO
var _mass := Vector3.ZERO
var _count := 0


func add_plane(point: Vector3, normal: Vector3) -> void:
    var n := normal.normalized()
    var d := n.dot(point)
    _a00 += n.x * n.x
    _a01 += n.x * n.y
    _a02 += n.x * n.z
    _a11 += n.y * n.y
    _a12 += n.y * n.z
    _a22 += n.z * n.z
    _atb  += n * d
    _mass += point
    _count += 1

func count() -> int:
    return _count

# The minimizing vertex, clamped to [cell_min, cell_max]. With no planes (should
# not happen for a surface cell) returns the cell centre.
func solve(cell_min: Vector3, cell_max: Vector3) -> Vector3:
    if _count == 0:
        return (cell_min + cell_max) * 0.5
    var centroid := _mass / float(_count)
    # Solve AᵀA·(x - c) = Aᵀb - AᵀA·c for the offset from the mass point, so the
    # null space of AᵀA leaves the vertex at the mass point rather than at origin.
    var rhs := _atb - _ata_mul(centroid)
    var v := centroid + _pseudo_solve(rhs)
    # If the solution lands outside the cell it's an unreliable extrapolation
    # (ill-conditioned feature solve); clamping it to a face still folds quads
    # against neighbours. Fall back to the mass point, which lies on the crossings
    # (inside the cell, on the surface) and keeps the quad near-planar.
    if v.x < cell_min.x or v.y < cell_min.y or v.z < cell_min.z \
            or v.x > cell_max.x or v.y > cell_max.y or v.z > cell_max.z:
        return centroid.clamp(cell_min, cell_max)
    return v


# --- internals ---

func _ata_mul(v: Vector3) -> Vector3:
    return Vector3(
        _a00 * v.x + _a01 * v.y + _a02 * v.z,
        _a01 * v.x + _a11 * v.y + _a12 * v.z,
        _a02 * v.x + _a12 * v.y + _a22 * v.z)

# x = Σ (vᵢ·rhs / λᵢ) vᵢ over eigenpairs whose λ clears the singular threshold.
func _pseudo_solve(rhs: Vector3) -> Vector3:
    var eig := _jacobi_eigen()
    var values: Vector3 = eig["values"]
    var vectors: Array  = eig["vectors"]
    var vmax := maxf(absf(values.x), maxf(absf(values.y), absf(values.z)))
    if vmax <= 0.0:
        return Vector3.ZERO
    var floor_val := vmax * SINGULAR_REL
    var x := Vector3.ZERO
    for i in 3:
        var lam: float = values[i]
        if absf(lam) <= floor_val:
            continue
        var axis: Vector3 = vectors[i]
        x += axis * (axis.dot(rhs) / lam)
    return x

# Eigen-decomposition of the symmetric AᵀA via cyclic Jacobi rotations.
# Returns {"values": Vector3, "vectors": [Vector3, Vector3, Vector3]} where
# vectors[i] is the unit eigenvector for values[i].
func _jacobi_eigen() -> Dictionary:
    var a := [
        [_a00, _a01, _a02],
        [_a01, _a11, _a12],
        [_a02, _a12, _a22],
    ]
    var v := [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
    ]
    for _sweep in 12:
        var p := 0
        var q := 1
        var best := absf(a[0][1])
        if absf(a[0][2]) > best:
            best = absf(a[0][2]); p = 0; q = 2
        if absf(a[1][2]) > best:
            best = absf(a[1][2]); p = 1; q = 2
        if best < 1e-14:
            break
        _rotate(a, v, p, q)
    return {
        "values":  Vector3(a[0][0], a[1][1], a[2][2]),
        "vectors": [
            Vector3(v[0][0], v[1][0], v[2][0]),
            Vector3(v[0][1], v[1][1], v[2][1]),
            Vector3(v[0][2], v[1][2], v[2][2]),
        ],
    }

# One Jacobi rotation J = [[c,-s],[s,c]] on the (p,q) plane, zeroing a[p][q].
# Updates the symmetric matrix a in place and accumulates eigenvectors v = v·J.
static func _rotate(a: Array, v: Array, p: int, q: int) -> void:
    var app: float = a[p][p]
    var aqq: float = a[q][q]
    var apq: float = a[p][q]
    var phi := 0.5 * atan2(2.0 * apq, app - aqq)
    var c := cos(phi)
    var s := sin(phi)
    var r := 3 - p - q   # the index not in {p, q}

    a[p][p] = c * c * app + 2.0 * s * c * apq + s * s * aqq
    a[q][q] = s * s * app - 2.0 * s * c * apq + c * c * aqq
    a[p][q] = 0.0
    a[q][p] = 0.0

    var arp: float = a[r][p]
    var arq: float = a[r][q]
    a[p][r] = c * arp + s * arq
    a[r][p] = a[p][r]
    a[q][r] = -s * arp + c * arq
    a[r][q] = a[q][r]

    for row in 3:
        var vp: float = v[row][p]
        var vq: float = v[row][q]
        v[row][p] = c * vp + s * vq
        v[row][q] = -s * vp + c * vq
