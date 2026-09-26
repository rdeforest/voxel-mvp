extends GutTest

# Pins Mat3::svd's signed-SVD convention through MpmSim.debug_svd: F = U·diag(σ)·Vᵀ with U and V
# proper rotations, σ sorted by magnitude, and sign(σ₂) = sign(det F). Reconstruction alone can't
# pin it — any even number of cancelling column flips still reconstructs F. Written ahead of the
# fast-SVD rewrite (doc 12).
#
# The first four tests are named by the input, not by a branch of today's routine: sign of det F,
# and the parity of the permutation that sorts the axis stretches by magnitude. With Jacobi+sort,
# that parity is det V before the flips, so the axis-aligned inputs reach the none / both / U / V
# reflection rows exactly; the rotated ones ride along. Mapping and the wrong fixes these catch:
# docs/bugs/closed/mpm-svd-reflection-sign.md.

const TOL := 1e-9


func _rot() -> Basis:
    var c1 := 3.0 / 5.0
    var s1 := 4.0 / 5.0
    var c2 := 20.0 / 29.0
    var s2 := 21.0 / 29.0

    return Basis(Vector3(c1, s1, 0.0), Vector3(-s1 * c2, c1 * c2, s2), Vector3(s1 * s2, -c1 * s2, c2))


func _stretch(sx: float, sy: float, sz: float) -> Basis:
    return Basis.from_scale(Vector3(sx, sy, sz))


func _assert_signed_svd(f: Basis, label: String) -> Dictionary:
    var r   := MpmSim.new().debug_svd(f)
    var det := f.determinant()

    assert_almost_eq(r["error"], 0.0, TOL, "%s: U·Σ·Vᵀ reconstructs F" % label)
    assert_almost_eq(r["det_u"], 1.0, TOL, "%s: det U = +1" % label)
    assert_almost_eq(r["det_v"], 1.0, TOL, "%s: det V = +1" % label)
    assert_eq(signf(r["s2"]), signf(det), "%s: sign(σ₂) = sign(det F) (σ₂ %s, det %s)" % [label, r["s2"], det])
    assert_almost_eq(r["s0"] * r["s1"] * r["s2"], det, TOL, "%s: Πσ = det F" % label)
    assert_true(r["s0"] >= r["s1"] and r["s1"] >= absf(r["s2"]), "%s: σ sorted by magnitude" % label)

    return r


func _assert_rotation_part(f: Basis, label: String, reflected: bool) -> void:
    var r := _assert_signed_svd(f, label)

    if reflected:
        assert_lt(r["s2"], 0.0, "%s: the reflection lands on σ₂" % label)
    else:
        assert_gt(r["s2"], 0.0, "%s: no reflection, σ₂ stays positive" % label)


# --- sign of det F × parity of the stretch order ---

func test_proper_even_stretch_order() -> void:
    _assert_rotation_part(_stretch(2.0, 1.0, 0.5), "diag(2, 1, 0.5)", false)
    _assert_rotation_part(_stretch(1.0, 0.5, 2.0), "diag(1, 0.5, 2)", false)


func test_proper_odd_stretch_order() -> void:
    _assert_rotation_part(_rot(), "pure rotation", false)
    _assert_rotation_part(_stretch(0.5, 1.0, 2.0), "diag(0.5, 1, 2)", false)
    _assert_rotation_part(_rot() * _stretch(0.5, 1.0, 2.0), "R·diag(0.5, 1, 2)", false)
    _assert_rotation_part(_rot() * _stretch(2.0, 1.0, 0.5), "R·diag(2, 1, 0.5)", false)


func test_reflection_even_stretch_order() -> void:
    _assert_rotation_part(_stretch(2.0, 1.0, -0.5), "diag(2, 1, -0.5)", true)
    _assert_rotation_part(_stretch(-1.0, 0.5, 2.0), "diag(-1, 0.5, 2)", true)
    _assert_rotation_part(_stretch(-1.0, -1.0, -1.0), "point inversion", true)


func test_reflection_odd_stretch_order() -> void:
    _assert_rotation_part(_stretch(-0.5, 1.0, 2.0), "diag(-0.5, 1, 2)", true)
    _assert_rotation_part(_stretch(1.0, -2.0, 0.5), "diag(1, -2, 0.5)", true)
    _assert_rotation_part(_rot() * _stretch(2.0, 1.0, -0.5), "R·diag(2, 1, -0.5)", true)
    _assert_rotation_part(_rot() * _stretch(-0.5, 1.0, 2.0), "R·diag(-0.5, 1, 2)", true)


func test_euler_rotations_and_stretches() -> void:
    var euler := Basis.from_euler(Vector3(0.3, 0.5, 0.7))

    _assert_rotation_part(Basis.IDENTITY, "identity", false)
    _assert_rotation_part(euler, "euler rotation", false)
    _assert_rotation_part(euler.scaled(Vector3(3.0, 1.5, 0.7)), "euler rotation·scale", false)
    _assert_rotation_part(euler.scaled(Vector3(3.0, 1.5, -0.7)), "euler rotation·reflection", true)


# --- degenerate spectra ---

func test_repeated_singular_values() -> void:
    var r  := _rot()
    var rt := r.transposed()

    _assert_rotation_part(r * _stretch(2.0, 2.0, 0.5) * rt, "σ = (2, 2, 0.5)", false)
    _assert_rotation_part(r * _stretch(2.0, 0.5, 0.5) * rt, "σ = (2, 0.5, 0.5)", false)
    _assert_rotation_part(r * _stretch(2.0, 0.5, -0.5) * rt, "σ = (2, 0.5, -0.5)", true)
    _assert_rotation_part(r * _stretch(1.0, 1.0, -1.0) * rt, "σ = (1, 1, -1)", true)
    _assert_rotation_part(r * -1.0, "-R", true)


func test_moderately_near_singular() -> void:
    var r  := _rot()
    var rt := r.transposed()

    _assert_rotation_part(r * _stretch(1.0, 1.0, 1e-3) * rt, "σ₂ = 1e-3", false)
    _assert_rotation_part(r * _stretch(1.0, 1.0, -1e-3) * rt, "σ₂ = -1e-3", true)
    _assert_rotation_part(r * _stretch(1.0, 1e-3, 1e-3) * rt, "σ = (1, 1e-3, 1e-3)", false)


func test_severely_near_singular_and_rank_deficient() -> void:
    pending("docs/bugs/mpm-svd-ill-conditioned-u.md: U loses orthonormality below σ_min/σ_max ≈ 1e-4 and is singular at rank ≤ 1")


# --- seeded random ---

func _random_rotation(rng: RandomNumberGenerator) -> Basis:
    var q := Quaternion(rng.randfn(), rng.randfn(), rng.randfn(), rng.randfn()).normalized()

    return Basis(q)


func _random_stretch(rng: RandomNumberGenerator, reflected: bool) -> Basis:
    var s := Vector3(rng.randf_range(0.2, 3.0), rng.randf_range(0.2, 3.0), rng.randf_range(0.2, 3.0))

    if reflected:
        s[rng.randi_range(0, 2)] *= -1.0

    return Basis.from_scale(s)


func test_random_rotation_stretch_rotation() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20260926

    for i in 64:
        var reflected := i % 2 == 1
        var f         := _random_rotation(rng) * _random_stretch(rng, reflected) * _random_rotation(rng)
        _assert_rotation_part(f, "random U·Σ·Vᵀ #%d" % i, reflected)


func test_random_general_matrices() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 1597

    # Nothing bounds these matrices' conditioning; this seed's worst is #10 at σ₂/σ₀ ≈ 6.8e-3, inside
    # the 1e-3 floor TOL holds to (docs/bugs/mpm-svd-ill-conditioned-u.md). Re-check if it changes.
    for i in 32:
        var f := Basis()
        for c in 3:
            f[c] = Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
        _assert_signed_svd(f, "random entries #%d" % i)
