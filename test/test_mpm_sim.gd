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


# A store whose only solid is a flat-topped pillar (top at world y = `top`), well above the
# generator surface so the pillar is the entire local collider.
func _pillar_store(top: int) -> EditStoreManager:
    var manager := EditStoreManager.new()
    manager.setup()
    manager.store.stamp_box(Vector3(0, top - 5, 0), Vector3(8, 10, 8), 0, 4, 1.0)
    return manager


func test_corotated_block_rests_on_an_sdf_pillar_without_penetrating() -> void:
    # The bug-fix proof: a stiff body must rest ON arbitrary terrain (contact resolved on the
    # grid via the SDF), not sink/pass through it — which is exactly what PBD couldn't do.
    var surface := SparseVoxelOctree.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    var top := int(surface) + 50
    var store := _pillar_store(top)

    var sim := MpmSim.new()
    sim.configure(Vector3(-16, top - 6, -16), 32, DX, Vector3(0, -9.8, 0), 5000.0, 0.2, top - 100.0)
    sim.set_sdf_collider(store.store)
    sim.set_material(1)
    var p_vol := (DX * 0.5) * (DX * 0.5) * (DX * 0.5)
    var p_mass := RHO * p_vol
    for cz in range(-2, 2):
        for cy in range(top + 1, top + 3):
            for cx in range(-2, 2):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), p_mass, p_vol)
    var start_y := sim.average_position().y

    for _i in 2000:
        sim.step(DT)

    assert_true(sim.is_finite(), "stable resting on the SDF pillar")
    assert_lt(sim.average_position().y, start_y - 0.5, "the block fell onto the pillar")
    # Caught by the pillar within ~1 cell of grid-contact softness (the SDF surface is at
    # `top`, but contact is enforced at grid nodes, so the rest sits up to a cell into the
    # surface at dx=1 m — finer grid / a penetration push-out tightens this later). The point
    # is it's CAUGHT, not fallen through (which would drop it metres to the grid floor).
    assert_gt(sim.lowest_y(), float(top) - 1.5, "caught by the pillar, didn't fall through (grid-resolved SDF contact)")
    assert_lt(sim.lowest_y(), float(top) + 2.0, "it actually reached the pillar top")


func _max_radius(sim: MpmSim) -> float:
    var r := 0.0
    for i in sim.particle_count():
        var p := sim.get_position(i)
        r = maxf(r, sqrt(p.x * p.x + p.z * p.z))
    return r

func _max_height(sim: MpmSim) -> float:
    var h := -INF
    for i in sim.particle_count():
        h = maxf(h, sim.get_position(i).y)
    return h


func _sand_column(friction: float, young: float, base: int, tall: int) -> MpmSim:
    var sim := MpmSim.new()
    sim.configure(Vector3(-16, -2, -16), 32, DX, Vector3(0, -9.8, 0), young, 0.3, FLOOR_Y)
    sim.set_material(2)
    sim.set_sand_friction(35.0)
    sim.set_contact_friction(friction)
    var p_vol := (DX * 0.5) * (DX * 0.5) * (DX * 0.5)
    var p_mass := RHO * p_vol
    var half := base / 2
    for cz in range(-half, half):
        for cy in range(0, tall):
            for cx in range(-half, half):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), p_mass, p_vol)
    return sim


func test_sand_column_collapses_to_a_stable_pile() -> void:
    # Drucker-Prager granular flow: a tall narrow column of sand must slump OUTWARD into a
    # shorter, wider pile that HOLDS (not a puddle), at a sand-like angle — behaviour an
    # elastic block (which keeps its shape) can't produce. This is the dirt-collapse half of
    # what MPM has to model honestly. The internal friction governs: across floor frictions
    # ≥ 0.05 the pile radius saturates (~6.2) at ~18-22° — the sand's own shear strength, not
    # the floor, sets the angle. (~20° vs the 35° input is the known MPM-sand calibration gap
    # — resolution + a Coulomb-correct contact friction tighten it; a fidelity-tuning item.)
    var sim := _sand_column(0.1, 1.0e5, 4, 10)
    var start_radius := _max_radius(sim)
    var start_height := _max_height(sim)

    for _i in 4000:
        sim.step(DT)

    assert_true(sim.is_finite(), "sand stayed finite")
    assert_gt(sim.lowest_y(), FLOOR_Y - 0.6, "the pile rests on the floor (no tunnelling)")
    var radius := _max_radius(sim)
    var height := _max_height(sim)
    assert_gt(radius, start_radius + 2.0, "the column slumped OUTWARD (granular flow), didn't hold its shape (%.1f -> %.1f)" % [start_radius, radius])
    assert_lt(height, start_height - 4.0, "the pile is much shorter than the column (%.1f -> %.1f)" % [start_height, height])
    var angle := rad_to_deg(atan(height / radius))
    assert_between(angle, 10.0, 45.0, "holds a stable sand-like pile — not a puddle (<5°) or a standing tower (>50°) (got %.1f°)" % angle)


func _all_positions(sim: MpmSim) -> Array:
    var out := []
    for i in sim.particle_count():
        out.append(sim.get_position(i))
    return out

func _max_drift(before: Array, after: Array) -> float:
    var d := 0.0
    for i in mini(before.size(), after.size()):
        d = maxf(d, before[i].distance_to(after[i]))
    return d

# Settle a block with sleeping on, stepping until the whole sim is asleep (or the budget runs out).
func _settle_asleep(sim: MpmSim, budget: int) -> bool:
    sim.set_sleeping(true)
    sim.set_sleep_params(0.2, 50, 0.5)
    sim.set_contact_friction(0.2)   # a little dissipation so it reaches full rest
    for _i in budget:
        sim.step(DT)
        if sim.is_asleep():
            return true
    return false


func test_sleeping_settles_to_a_no_op_and_preserves_state() -> void:
    # Sparse sleeping (doc 12): a settled structure goes fully asleep, after which step() is a
    # NO-OP that preserves state exactly — the lossless "design the boundary away" path (no
    # rasterise-to-field, so F/stress are kept, not dropped).
    var sim := _block(Vector3i(-2, 1, -2), Vector3i(2, 3, 2))
    assert_true(_settle_asleep(sim, 6000), "the settled block went fully to sleep (awake_count -> 0)")

    var before := _all_positions(sim)
    for _i in 300:
        sim.step(DT)
    assert_eq(sim.awake_count(), 0, "still asleep")
    assert_almost_eq(_max_drift(before, _all_positions(sim)), 0.0, 1e-12, "asleep steps are an exact no-op — state preserved losslessly")


func test_a_dropped_block_wakes_the_sleeping_pile() -> void:
    # Wake-on-disturbance: a sleeping pile must re-activate and respond when something lands on
    # it (the grid velocity from the impact exceeds the wake threshold).
    var sim := _block(Vector3i(-2, 1, -2), Vector3i(2, 3, 2))
    assert_true(_settle_asleep(sim, 6000), "the pile slept")
    sim.set_sleep_params(0.2, 50, 0.1)   # wake threshold the landing load can clear
    var pile_count := sim.particle_count()
    var pile_before := _all_positions(sim)

    # Drop a pile-sized block from well above onto the sleeping pile (a clear impact).
    var p_vol := (DX * 0.5) * (DX * 0.5) * (DX * 0.5)
    var p_mass := RHO * p_vol
    for cz in range(-2, 2):
        for cy in range(12, 14):
            for cx in range(-2, 2):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), p_mass, p_vol)
    assert_gt(sim.awake_count(), 0, "adding the falling block woke the sim")

    for _i in 2000:
        sim.step(DT)

    # A woken pile moves MEASURABLY (contrast: a pile that never wakes drifts exactly 0.0,
    # since asleep particles don't advect). The dent is only modest because once awake the
    # heavy pile re-supports the load — that magnitude is physics; the nonzero-ness is the proof.
    var pile_drift := _max_drift(pile_before, _all_positions(sim).slice(0, pile_count))
    assert_gt(pile_drift, 0.03, "the impact woke and moved the sleeping pile (wake-on-disturbance), drift %.3f" % pile_drift)
    assert_true(sim.is_finite(), "stayed finite through wake + impact")


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
