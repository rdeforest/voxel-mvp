extends RefCounted

const TICK_DT := 1.0 / 60.0


static func run() -> void:
    var mode := OS.get_environment("DIAG_MODE")
    if mode == "" or mode == "terrain":
        _terrain_block(4, 30, 3000)
    if mode == "" or mode == "tilt":
        for fric in [0.35, 0.9]:
            for deg in [0.0, 5.0, 10.0, 15.0, 19.0, 25.0, 35.0]:
                _tilted(deg, fric)


static func _surf(x: float, z: float) -> float:
    return EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


static func _slope_deg(x: float, z: float) -> float:
    var h := 0.5
    var gx := (_surf(x + h, z) - _surf(x - h, z)) / (2 * h)
    var gz := (_surf(x, z + h) - _surf(x, z - h)) / (2 * h)
    return rad_to_deg(atan(sqrt(gx * gx + gz * gz)))


static func _sdf_grad(store: EditStore, p: Vector3) -> Vector3:
    var h := 0.5
    return Vector3(store.sample(p + Vector3(h, 0, 0)) - store.sample(p - Vector3(h, 0, 0)),
        store.sample(p + Vector3(0, h, 0)) - store.sample(p - Vector3(0, h, 0)),
        store.sample(p + Vector3(0, 0, h)) - store.sample(p - Vector3(0, 0, h))) / (2 * h)


static func _terrain_block(size: int, lift: int, ticks: int) -> void:
    var mgr := EditStoreManager.new()
    mgr.setup()
    var store := mgr.store
    var base := int(_surf(0.0, 0.0)) + lift
    store.stamp_box(Vector3(0.5, float(base) + size * 0.5 + 0.5, 0.5), Vector3.ONE * size, 0, 1, 1.0)
    var reach := size / 2 + 2
    var cells: Array[Vector3i] = []
    for z in range(-reach, reach + 1):
        for y in range(base - 2, base + size + 4):
            for x in range(-reach, reach + 1):
                if TerrainProbe.is_solid(store, Vector3i(x, y, z)):
                    cells.append(Vector3i(x, y, z))
    var ms := MpmStructure.new()
    ms.setup(store)
    var n := ms.thaw_cells(cells, EditSource.Kind.SCOUT)
    var sim: MpmSim = ms._sim
    print("thawed %d cells, %d particles; surface(0,0)=%.2f slope(0,0)=%.1f deg" % [n, sim.particle_count(), _surf(0, 0), _slope_deg(0, 0)])
    var prev := sim.average_position()
    for t in ticks:
        ms.tick(TICK_DT)
        if ms.active_count() == 0:
            print("FROZE at tick %d" % t)
            return
        if t % 150 == 0 or t == ticks - 1:
            var c := sim.average_position()
            var v := (c - prev) / TICK_DT
            prev = c
            var contact := 0
            var sdfmin := 1e9
            for i in sim.particle_count():
                var s := store.sample(sim.get_position(i))
                sdfmin = minf(sdfmin, s)
                if s < 0.6:
                    contact += 1
            var g := _sdf_grad(store, Vector3(c.x, _surf(c.x, c.z), c.z))
            var slope := _slope_deg(c.x, c.z)
            var nslope := rad_to_deg(acos(clampf(g.normalized().y, -1, 1)))
            # mean displacement of particles in contact vs not
            var dc := Vector3(); var dn := Vector3(); var nc := 0; var nn := 0
            for i in sim.particle_count():
                if store.sample(sim.get_position(i)) < 0.6:
                    dc += sim.get_displacement(i); nc += 1
                else:
                    dn += sim.get_displacement(i); nn += 1
            print("t=%4d com=(%.1f,%.1f,%.1f) clearance=%.2f v=(%.2f,%.2f,%.2f)|%.2f| m/s maxdisp=%.4f slope(height)=%.1f slope(sdfgrad)=%.1f |grad|=%.2f contact=%d/%d sdfmin=%.2f dC=%.4f dN=%.4f" % [
                t, c.x, c.y, c.z, sim.lowest_y() - _surf(c.x, c.z), v.x, v.y, v.z, v.length() / 150.0,
                sim.max_displacement(), slope, nslope, g.length(), contact, sim.particle_count(), sdfmin,
                (dc / maxf(nc, 1)).length(), (dn / maxf(nn, 1)).length()])
    print("NOT frozen after %d ticks" % ticks)
    ms.free()


# A flat floor (y=0, no SDF collider) with gravity tilted by `deg` — geometrically identical to a
# slope of that angle, isolating the contact law from terrain normals.
static func _tilted(deg: float, fric: float) -> void:
    var a := deg_to_rad(deg)
    var sim := MpmSim.new()
    sim.configure(Vector3.ZERO, 48, 1.0, Vector3(9.8 * sin(a), -9.8 * cos(a), 0), 0.0)
    sim.set_iterations(4)
    sim.set_elastic(1.0, 0.5)
    sim.set_contact_friction(fric)
    sim.set_damping(0.03)
    sim.set_recenter(true)
    var pv := 0.125
    for cz in range(-2, 2):
        for cy in range(0, 4):
            for cx in range(-2, 2):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), 400.0 * pv, pv)
    var settled := 0
    var froze := -1
    var x0 := 0.0
    for t in 1200:
        if t == 600:
            x0 = sim.average_position().x
        sim.step(TICK_DT)
        if sim.max_displacement() < 0.01:
            settled += 1
            if settled >= 30 and froze < 0:
                froze = t
        else:
            settled = 0
    var c := sim.average_position()
    var slide := (c.x - x0) / (600 * TICK_DT)
    var theory := 0.0
    print("tilt %4.1f deg fric %.2f: slide speed (t 600-1200) %.3f m/s  maxdisp %.4f  settle-freeze tick %d" % [deg, fric, slide, sim.max_displacement(), froze])
