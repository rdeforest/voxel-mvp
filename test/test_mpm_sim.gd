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
