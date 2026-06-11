extends GutTest

# MPM spike (doc 12) increment 1: the MLS-MPM core must run stably and resolve contact with
# a collider — the thing PBD lacked. Drop an elastic block onto a floor and pin the
# structural facts headlessly: it stays finite (doesn't blow up), falls under gravity, and
# lands ON the floor without tunnelling through it. Squish/settle fidelity and the
# beam-on-peak / dirt-slide / sleeping-load-bearer scenes are later increments.

const DX        := 1.0
const FLOOR_Y   := 0.0
const DT        := 0.001
const STEPS     := 1500
const RHO       := 400.0
const E         := 2000.0
const NU        := 0.2


# An elastic block spanning the given cell box, 2 particles per axis per cell (8/cell),
# dropped over the floor. Returns the configured, populated sim.
func _block(lo: Vector3i, hi: Vector3i) -> MpmSim:
    var sim := MpmSim.new()
    sim.configure(Vector3(-16, -2, -16), 32, DX, Vector3(0, -9.8, 0), E, NU, FLOOR_Y)
    var p_vol := (DX * 0.5) * (DX * 0.5) * (DX * 0.5)   # 8 particles per 1 m³ cell
    var p_mass := RHO * p_vol
    for cz in range(lo.z, hi.z):
        for cy in range(lo.y, hi.y):
            for cx in range(lo.x, hi.x):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), p_mass, p_vol)
    return sim


func test_block_falls_and_rests_on_the_floor_without_tunnelling() -> void:
    var sim := _block(Vector3i(-2, 4, -2), Vector3i(2, 6, 2))
    assert_eq(sim.particle_count(), 256, "4*2*4 cells * 8 particles")
    var start_y := sim.average_position().y

    for _i in STEPS:
        sim.step(DT)

    assert_true(sim.is_finite(), "the solver stayed finite (didn't blow up) — stability of the core loop")
    var end_avg := sim.average_position().y
    var end_low := sim.lowest_y()

    assert_lt(end_avg, start_y - 2.0, "the block fell substantially under gravity (%.2f -> %.2f)" % [start_y, end_avg])
    assert_gt(end_low, FLOOR_Y - 0.6, "no tunnelling — the lowest particle stayed at/above the floor (lowest %.2f)" % end_low)
    assert_lt(end_low, FLOOR_Y + 1.5, "it actually reached the floor, didn't hover (lowest %.2f)" % end_low)
    assert_gt(end_avg, FLOOR_Y - 0.2, "the block rests on the floor, not below it (avg %.2f)" % end_avg)


func _check_svd(basis: Basis, label: String) -> void:
    var r := MpmSim.new().debug_svd(basis)
    assert_almost_eq(r["error"], 0.0, 1e-9, "%s: U·Σ·Vᵀ reconstructs the matrix" % label)
    assert_almost_eq(r["det_u"], 1.0, 1e-9, "%s: U is a proper rotation" % label)
    assert_almost_eq(r["det_v"], 1.0, 1e-9, "%s: V is a proper rotation" % label)
    # σ₀·σ₁·σ₂ = det(F) (signed) — the reflection rides on the smallest singular value.
    var prod: float = r["s0"] * r["s1"] * r["s2"]
    assert_almost_eq(prod, basis.determinant(), 1e-9, "%s: Πσ = det(F)" % label)
    assert_true(r["s0"] >= r["s1"] and r["s1"] >= abs(r["s2"]), "%s: singular values sorted by magnitude" % label)


func test_svd_reconstructs_known_matrices() -> void:
    _check_svd(Basis.IDENTITY, "identity")
    _check_svd(Basis.IDENTITY.scaled(Vector3(2.0, 1.0, 0.5)), "diagonal scale")
    _check_svd(Basis.from_euler(Vector3(0.3, 0.5, 0.7)), "pure rotation")
    _check_svd(Basis.from_euler(Vector3(0.3, 0.5, 0.7)).scaled(Vector3(3.0, 1.5, 0.7)), "rotation·scale")


func test_svd_signed_convention_handles_reflection() -> void:
    # A negative determinant (reflection) must come back as ONE negative singular value with
    # U, V still proper rotations — the convention fixed-corotated/Drucker-Prager rely on.
    var reflected := Basis.IDENTITY.scaled(Vector3(2.0, 1.0, -0.5))
    var r := MpmSim.new().debug_svd(reflected)
    assert_almost_eq(r["error"], 0.0, 1e-9, "reconstructs the reflected matrix")
    assert_almost_eq(r["det_u"], 1.0, 1e-9, "U stays a rotation")
    assert_almost_eq(r["det_v"], 1.0, 1e-9, "V stays a rotation")
    assert_lt(r["s2"], 0.0, "the reflection is absorbed as a negative smallest singular value")


func test_corotated_block_also_falls_and_rests() -> void:
    # The fixed-corotated model (which uses the SVD every step) must run as stably as
    # neo-Hookean on the drop: stay finite, fall, land on the floor without tunnelling.
    var sim := _block(Vector3i(-2, 4, -2), Vector3i(2, 6, 2))
    sim.set_material(1)
    var start_y := sim.average_position().y
    for _i in STEPS:
        sim.step(DT)
    assert_true(sim.is_finite(), "fixed-corotated stayed finite over the drop")
    assert_lt(sim.average_position().y, start_y - 2.0, "the corotated block fell")
    assert_gt(sim.lowest_y(), FLOOR_Y - 0.6, "no tunnelling under fixed-corotated")


func test_settles_rather_than_gaining_energy() -> void:
    # A spike sanity floor: by the end the block isn't *gaining* kinetic energy (no blow-up
    # masquerading as finite). Compared against the free-fall energy at impact, not zero —
    # elastic squish + APIC leave some residual jiggle this early in the spike.
    var sim := _block(Vector3i(-2, 4, -2), Vector3i(2, 6, 2))
    for _i in STEPS:
        sim.step(DT)
    assert_true(sim.is_finite(), "finite at the end")
    var total_mass := 256.0 * RHO * (DX * 0.5) * (DX * 0.5) * (DX * 0.5)
    var impact_energy := total_mass * 9.8 * 4.0   # m g h, h ~ drop height
    assert_lt(sim.kinetic_energy(), impact_energy, "end KE is below the free-fall impact energy (settling, not exploding)")
