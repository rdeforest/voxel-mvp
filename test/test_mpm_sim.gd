extends GutTest

# PB-MPM solver (doc 12, Lewin 2024). Headless validation: the 3×3 SVD, the elastic constraint
# behaviour (a body falls, rests on terrain without tunnelling, holds together), UNCONDITIONAL
# STABILITY at large timesteps (the whole point — explicit MLS-MPM needed dt~1e-3; PB-MPM stays
# stable at dt orders of magnitude larger), and sparse sleeping. PB-MPM sand is the next
# increment (the granular test is pending).

const DX      := 1.0
const FLOOR_Y := 0.0
const DT      := 0.02
const ITERS   := 4
const RATIO   := 1.0   # elasticity_ratio: 1 = rotation (shape-preserving) target
const RELAX   := 0.5
const RHO     := 400.0


func _elastic_block(lo: Vector3i, hi: Vector3i, dt := DT) -> MpmSim:
    var sim := MpmSim.new()
    sim.configure(Vector3(-16, -2, -16), 32, DX, Vector3(0, -9.8, 0), FLOOR_Y)
    sim.set_iterations(ITERS)
    sim.set_elastic(RATIO, RELAX)
    var p_vol := (DX * 0.5) * (DX * 0.5) * (DX * 0.5)
    var p_mass := RHO * p_vol
    for cz in range(lo.z, hi.z):
        for cy in range(lo.y, hi.y):
            for cx in range(lo.x, hi.x):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), p_mass, p_vol)
    return sim


# --- SVD (unchanged from the spike; the riskiest numerical code) ---

func _check_svd(basis: Basis, label: String) -> void:
    var r := MpmSim.new().debug_svd(basis)
    assert_almost_eq(r["error"], 0.0, 1e-9, "%s: U·Σ·Vᵀ reconstructs the matrix" % label)
    assert_almost_eq(r["det_u"], 1.0, 1e-9, "%s: U is a proper rotation" % label)
    assert_almost_eq(r["det_v"], 1.0, 1e-9, "%s: V is a proper rotation" % label)
    var prod: float = r["s0"] * r["s1"] * r["s2"]
    assert_almost_eq(prod, basis.determinant(), 1e-9, "%s: Πσ = det(F)" % label)
    assert_true(r["s0"] >= r["s1"] and r["s1"] >= abs(r["s2"]), "%s: singular values sorted by magnitude" % label)

func test_svd_reconstructs_known_matrices() -> void:
    _check_svd(Basis.IDENTITY, "identity")
    _check_svd(Basis.IDENTITY.scaled(Vector3(2.0, 1.0, 0.5)), "diagonal scale")
    _check_svd(Basis.from_euler(Vector3(0.3, 0.5, 0.7)), "pure rotation")
    _check_svd(Basis.from_euler(Vector3(0.3, 0.5, 0.7)).scaled(Vector3(3.0, 1.5, 0.7)), "rotation·scale")

func test_svd_signed_convention_handles_reflection() -> void:
    var r := MpmSim.new().debug_svd(Basis.IDENTITY.scaled(Vector3(2.0, 1.0, -0.5)))
    assert_almost_eq(r["error"], 0.0, 1e-9, "reconstructs the reflected matrix")
    assert_almost_eq(r["det_u"], 1.0, 1e-9, "U stays a rotation")
    assert_almost_eq(r["det_v"], 1.0, 1e-9, "V stays a rotation")
    assert_lt(r["s2"], 0.0, "the reflection is absorbed as a negative smallest singular value")


# --- PB-MPM elastic ---

func test_elastic_block_falls_and_rests_without_tunnelling() -> void:
    var sim := _elastic_block(Vector3i(-2, 4, -2), Vector3i(2, 6, 2))
    assert_eq(sim.particle_count(), 256, "4*2*4 cells * 8 particles")
    var start_y := sim.average_position().y

    for _i in 200:
        sim.step(DT)

    assert_true(sim.is_finite(), "the solver stayed finite")
    var end_avg := sim.average_position().y
    assert_lt(end_avg, start_y - 2.0, "the block fell under gravity (%.2f -> %.2f)" % [start_y, end_avg])
    assert_gt(sim.lowest_y(), FLOOR_Y - 0.6, "no tunnelling — rests at/above the floor (lowest %.2f)" % sim.lowest_y())
    assert_lt(sim.lowest_y(), FLOOR_Y + 1.5, "it reached the floor, didn't hover")


func test_unconditional_stability_at_large_timestep() -> void:
    # The headline of PB-MPM: stable at a timestep that would blow explicit MLS-MPM to NaN.
    # Explicit needed dt~1e-3 (CFL); here we run dt = 0.2 (200x) and it must stay finite + fall.
    var big_dt := 0.2
    var sim := _elastic_block(Vector3i(-2, 6, -2), Vector3i(2, 8, 2), big_dt)
    var start_y := sim.average_position().y
    for _i in 120:
        sim.step(big_dt)
    assert_true(sim.is_finite(), "PB-MPM stayed finite at dt=0.2 (explicit would have exploded)")
    assert_lt(sim.average_position().y, start_y - 2.0, "still falls correctly at the large timestep")
    assert_gt(sim.lowest_y(), FLOOR_Y - 1.0, "and rests on the floor, no tunnel-through at dt=0.2")


func test_block_holds_together_doesnt_shatter() -> void:
    # An elastic block must stay a coherent body — its particle spread shouldn't explode.
    var sim := _elastic_block(Vector3i(-2, 4, -2), Vector3i(2, 6, 2))
    var start_extent := _extent(sim)
    for _i in 200:
        sim.step(DT)
    assert_true(sim.is_finite(), "finite")
    assert_lt(_extent(sim), start_extent * 2.0, "the block held together (didn't shatter/explode)")


func _extent(sim: MpmSim) -> float:
    var c := sim.average_position()
    var e := 0.0
    for i in sim.particle_count():
        e = maxf(e, sim.get_position(i).distance_to(c))
    return e


# --- SDF collider (the beam-on-terrain bug-fix mechanism, now under PB-MPM) ---

func _pillar_store(top: int) -> EditStoreManager:
    var manager := EditStoreManager.new()
    manager.setup()
    manager.store.stamp_box(Vector3(0, top - 5, 0), Vector3(8, 10, 8), 0, 4, 1.0)
    return manager

func test_elastic_block_rests_on_an_sdf_pillar() -> void:
    var surface := SparseVoxelOctree.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    var top := int(surface) + 50
    var store := _pillar_store(top)

    var sim := MpmSim.new()
    sim.configure(Vector3(-16, top - 6, -16), 32, DX, Vector3(0, -9.8, 0), top - 100.0)
    sim.set_iterations(ITERS)
    sim.set_elastic(RATIO, RELAX)
    sim.set_sdf_collider(store.store)
    var p_vol := (DX * 0.5) * (DX * 0.5) * (DX * 0.5)
    for cz in range(-2, 2):
        for cy in range(top + 1, top + 3):
            for cx in range(-2, 2):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), RHO * p_vol, p_vol)
    var start_y := sim.average_position().y

    for _i in 300:
        sim.step(DT)

    assert_true(sim.is_finite(), "stable resting on the SDF pillar")
    assert_lt(sim.average_position().y, start_y, "the block fell onto the pillar")
    assert_gt(sim.lowest_y(), float(top) - 1.5, "caught by the pillar, didn't fall through (grid-resolved SDF contact)")


# --- Sparse sleeping (PB-MPM) ---

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

func _settle_asleep(sim: MpmSim, budget: int) -> bool:
    sim.set_sleeping(true)
    sim.set_sleep_params(0.01, 30, 0.05)
    for _i in budget:
        sim.step(DT)
        if sim.is_asleep():
            return true
    return false

func test_sleeping_settles_to_a_no_op_and_preserves_state() -> void:
    var sim := _elastic_block(Vector3i(-2, 1, -2), Vector3i(2, 3, 2))
    assert_true(_settle_asleep(sim, 1000), "the settled block went fully to sleep (awake_count -> 0)")
    var before := _all_positions(sim)
    for _i in 200:
        sim.step(DT)
    assert_eq(sim.awake_count(), 0, "still asleep")
    assert_almost_eq(_max_drift(before, _all_positions(sim)), 0.0, 1e-12, "asleep steps are an exact no-op — state preserved losslessly")

func test_a_dropped_block_wakes_the_sleeping_pile() -> void:
    var sim := _elastic_block(Vector3i(-2, 1, -2), Vector3i(2, 3, 2))
    assert_true(_settle_asleep(sim, 1000), "the pile slept")
    sim.set_sleep_params(0.01, 30, 0.02)
    var pile_count := sim.particle_count()
    var pile_before := _all_positions(sim)
    var p_vol := (DX * 0.5) * (DX * 0.5) * (DX * 0.5)
    for cz in range(-2, 2):
        for cy in range(12, 14):
            for cx in range(-2, 2):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), RHO * p_vol, p_vol)
    assert_gt(sim.awake_count(), 0, "adding the falling block woke the sim")
    for _i in 200:
        sim.step(DT)
    var pile_drift := _max_drift(pile_before, _all_positions(sim).slice(0, pile_count))
    assert_gt(pile_drift, 0.03, "the impact woke and moved the sleeping pile (wake-on-disturbance), drift %.3f" % pile_drift)
    assert_true(sim.is_finite(), "stayed finite through wake + impact")


# --- Pending: PB-MPM sand (Drucker-Prager on the integrated F + logJp) ---

func test_recenter_grid_follows_the_material() -> void:
    # With re-centering on, the world-fixed grid slides to follow the material, so a block can
    # travel far past the grid's half-extent (otherwise a hard domain wall) — what fixes the
    # "bouncing off invisible walls" in the demo. Free-fall a block in a small grid with no floor.
    var sim := MpmSim.new()
    sim.configure(Vector3(-12, -12, -12), 24, DX, Vector3(0, -9.8, 0), -1.0e9)
    sim.set_iterations(4)
    sim.set_elastic(1.0, 0.5)
    sim.set_recenter(true)
    var p_vol := (DX * 0.5) * (DX * 0.5) * (DX * 0.5)
    for cz in range(-1, 1):
        for cy in range(-1, 1):
            for cx in range(-1, 1):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), RHO * p_vol, p_vol)
    var start_y := sim.average_position().y

    for _i in 100:
        sim.step(0.05)

    assert_true(sim.is_finite(), "stable while free-falling")
    assert_lt(sim.average_position().y, start_y - 20.0, "fell far past the 12 m grid half-extent — the grid followed (no wall)")


func test_elastic_block_rests_on_real_generator_terrain() -> void:
    # The `mpmdemo` scenario headlessly: an elastic block dropped onto the REAL procedural
    # terrain (the EditStore generator as the SDF collider) must fall and rest on it, finite.
    var store := EditStoreManager.new()
    store.setup()
    var surface := SparseVoxelOctree.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    var top := int(surface)

    var sim := MpmSim.new()
    sim.configure(Vector3(-20, top - 30, -20), 50, DX, Vector3(0, -9.8, 0), -1.0e9)
    sim.set_iterations(4)
    sim.set_elastic(1.0, 0.5)
    sim.set_sdf_collider(store.store)
    var p_vol := (DX * 0.5) * (DX * 0.5) * (DX * 0.5)
    for cz in range(-2, 2):
        for cy in range(top + 4, top + 6):
            for cx in range(-2, 2):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), RHO * p_vol, p_vol)
    var start_y := sim.average_position().y

    for _i in 150:
        sim.step(0.05)

    assert_true(sim.is_finite(), "stable on the real terrain")
    assert_lt(sim.average_position().y, start_y, "the block fell")
    # The C++ generator surface is ~168 here (the GDScript terrain_surface says 170 — a ~2 m
    # mismatch); the block must rest near it, well above the grid floor at top-30.
    assert_gt(sim.lowest_y(), float(top) - 6.0, "rests near the terrain surface, didn't fall through")
    assert_lt(sim.lowest_y(), float(top) + 4.0, "it reached the terrain")


func test_pbmpm_sand_repose_pile() -> void:
    # The PB-MPM sand path (Drucker-Prager return-mapping + logJp) is implemented in
    # mpm_material.cpp, but its parameters aren't dialled in: with deviatoric viscosity it
    # spreads to a near-flat puddle (the damping that stabilises it also removes the shear
    # strength that should hold a repose pile); without it the constraint injects energy.
    # Needs the EA reference constants + reworking the granular damping. Tuning deferred.
    pending("PB-MPM sand: Drucker-Prager implemented; repose-angle tuning deferred (viscosity vs shear-strength conflict)")
