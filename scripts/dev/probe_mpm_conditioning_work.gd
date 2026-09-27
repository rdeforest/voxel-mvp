extends RefCounted

# Scenarios: the game's thaws through MpmStructure (terrain spheres, a floating block — the
# detachment shape), then bare-MpmSim stress cases (the dt = 0.2 drop, an untuned sand column).

const RHO       := 400.0
const TICK_DT   := 1.0 / 60.0
const MAX_TICKS := 3000   # PROBE_MAX_TICKS overrides it, for quicker A/B timing runs


static func run() -> void:
    for radius in [3.0, 5.0]:
        var mgr := _terrain()
        var top := _surface(0.0, 0.0)
        _thaw("sphere r=%s" % radius, mgr, func(ms: MpmStructure) -> int:
            return ms.thaw_sphere(Vector3(0.5, top - 3.0, 0.5), radius))

    var slope := _terrain()
    var slope_top := _surface(15.0, -16.0)
    _thaw("sphere r=3 at (15,-16)", slope, func(ms: MpmStructure) -> int:
        return ms.thaw_sphere(Vector3(15.5, slope_top - 2.0, -15.5), 3.0))

    for spec in [[10, 30], [4, 30], [4, 80]]:
        var block := _terrain()
        var cells := _floating_block(block.store, spec[0], spec[1])
        _thaw("floating box stamp %d, %d m up" % spec, block, func(ms: MpmStructure) -> int:
            return ms.thaw_cells(cells))

    _stepped("elastic drop dt=0.02 (8x4x8 cells)", _elastic_drop(Vector3i(4, 2, 4)), 0.02, 300)

    for dt in [1.0 / 60.0, 0.05, 0.1, 0.2]:
        _stepped("elastic drop dt=%.3f" % dt, _elastic_drop(Vector3i(2, 1, 2)), dt, int(24.0 / dt))

    _stepped("sand column 4x10x4, no viscosity", _sand_column(0.0), 0.02, 600)
    _stepped("sand column 4x10x4, viscosity 0.1", _sand_column(0.1), 0.02, 600)


static func _terrain() -> EditStoreManager:
    var mgr := EditStoreManager.new()
    mgr.setup()

    return mgr


static func _surface(x: float, z: float) -> float:
    return EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


static func _floating_block(store: EditStore, size: int, lift: int) -> Array[Vector3i]:
    var base   := int(_surface(0.0, 0.0)) + lift
    var centre := Vector3(0.5, float(base) + size * 0.5 + 0.5, 0.5)
    store.stamp_box(centre, Vector3.ONE * size, 0, 1, 1.0)

    var reach := size / 2 + 2
    var cells: Array[Vector3i] = []
    for z in range(-reach, reach + 1):
        for y in range(base - 2, base + size + 4):
            for x in range(-reach, reach + 1):
                if TerrainProbe.is_solid(store, Vector3i(x, y, z)):
                    cells.append(Vector3i(x, y, z))

    return cells


static func _thaw(label: String, mgr: EditStoreManager, thaw: Callable) -> void:
    var ms := MpmStructure.new()
    ms.setup(mgr.store)

    var thawed: int = thaw.call(ms)
    var sim         := ms._sim
    var particles   := sim.particle_count()
    var ticks       := 0
    var usec        := 0

    _reset_ratio(sim)

    var cap := int(OS.get_environment("PROBE_MAX_TICKS")) if OS.has_environment("PROBE_MAX_TICKS") else MAX_TICKS

    while ms.active_count() > 0 and ticks < cap:
        var t0 := Time.get_ticks_usec()
        ms.tick(TICK_DT)
        usec  += Time.get_ticks_usec() - t0
        ticks += 1

    _report(label, "thawed %d cells, %d particles, %d ticks%s" % [thawed, particles, ticks,
        "" if ms.active_count() == 0 else " (NOT frozen)"], sim, usec, ticks)
    ms.free()


static func _stepped(label: String, sim: MpmSim, dt: float, steps: int) -> void:
    var particles := sim.particle_count()
    var t0        := Time.get_ticks_usec()

    _reset_ratio(sim)

    for _i in steps:
        sim.step(dt)

    _report(label, "%d particles, %d steps, finite %s" % [particles, steps, sim.is_finite()], sim,
        Time.get_ticks_usec() - t0, steps)


static func _report(label: String, detail: String, sim: MpmSim, usec: int, steps: int) -> void:
    var ratio := "n/a"

    if sim.has_method("get_min_sigma_ratio"):
        ratio = String.num_scientific(sim.get_min_sigma_ratio())

    print("%-36s min|s2|/s0 %-12s %8.2f ms/step  %s" % [label, ratio,
        float(usec) / 1000.0 / maxf(steps, 1), detail])


static func _reset_ratio(sim: MpmSim) -> void:
    if sim.has_method("reset_min_sigma_ratio"):
        sim.reset_min_sigma_ratio()


static func _fill(sim: MpmSim, lo: Vector3i, hi: Vector3i) -> void:
    var p_vol := 0.125

    for cz in range(lo.z, hi.z):
        for cy in range(lo.y, hi.y):
            for cx in range(lo.x, hi.x):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), RHO * p_vol, p_vol)


static func _elastic_drop(half: Vector3i) -> MpmSim:
    var sim := MpmSim.new()
    sim.configure(Vector3(-16, -2, -16), 32, 1.0, Vector3(0, -9.8, 0), 0.0)
    sim.set_iterations(4)
    sim.set_elastic(1.0, 0.5)
    _fill(sim, Vector3i(-half.x, 6, -half.z), Vector3i(half.x, 6 + 2 * half.y, half.z))

    return sim


static func _sand_column(viscosity: float) -> MpmSim:
    var sim := MpmSim.new()
    sim.configure(Vector3(-16, -2, -16), 32, 1.0, Vector3(0, -9.8, 0), 0.0)
    sim.set_material(2)
    sim.set_iterations(4)
    sim.set_elastic(1.0, 0.5)
    sim.set_sand_friction(35.0)
    sim.set_contact_friction(0.1)
    sim.set_viscosity(viscosity)
    _fill(sim, Vector3i(-2, 0, -2), Vector3i(2, 10, 2))

    return sim
