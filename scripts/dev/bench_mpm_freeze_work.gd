extends RefCounted

# Settles a thaw without freezing it, then times the freeze's store write on fresh copies of the
# settled store, so every repeat deposits into the same field.

const REPEATS := 5


static func run() -> void:
    var top := int(EditStore.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED))

    var buried := _manager()
    var cells: Array[Vector3i] = []
    for x in 9:
        for y in 9:
            for z in 9:
                cells.append(Vector3i(x - 4, top - 16 + y, z - 4))
    _bench("buried 9^3 block", buried, cells)

    var floating := _manager()
    var base     := top + 30
    floating.store.stamp_box(Vector3(0.5, float(base) + 5.5, 0.5), Vector3(10, 10, 10), 0, 1, 1.0)
    var block: Array[Vector3i] = []
    for z in range(-7, 8):
        for y in range(base - 2, base + 14):
            for x in range(-7, 8):
                if TerrainProbe.is_solid(floating.store, Vector3i(x, y, z)):
                    block.append(Vector3i(x, y, z))
    _bench("floating 10^3 block", floating, block)


static func _manager() -> EditStoreManager:
    var mgr := EditStoreManager.new()
    mgr.setup()
    return mgr


static func _bench(label: String, mgr: EditStoreManager, cells: Array[Vector3i]) -> void:
    var ms := MpmStructure.new()
    ms.setup(mgr.store)
    var thawed := ms.thaw_cells(cells, EditSource.Kind.SCOUT)
    var frames := _settle(ms)
    var blob   := mgr.store.serialize()

    var best := INF
    var region: Dictionary
    for _i in REPEATS:
        var copy := _manager()
        copy.store.deserialize(blob)
        var t0 := Time.get_ticks_usec()
        region = ms._sim.rasterize_to_store(copy.store, 1.0, MpmStructure.FREEZE_RADIUS, 1)
        best = minf(best, Time.get_ticks_usec() - t0)

    print("%s: thawed %d, %d particles, settled in %d frames, freeze dim %d, best of %d %.0f usec, flips %s" % [
        label, thawed, ms.active_count(), frames, region.get("dim", 0), REPEATS, best, _flip_counts(region)])
    ms.free()


static func _settle(ms: MpmStructure) -> int:
    var settled := 0
    for frame in 12000:
        ms._sim.step(1.0 / 60.0)
        settled = settled + 1 if ms._sim.max_displacement() < MpmStructure.SETTLE_DISP else 0
        if settled >= MpmStructure.SETTLE_FRAMES:
            return frame + 1
    return -1


static func _flip_counts(region: Dictionary) -> String:
    if not region.has("solid"):
        return "unmeasured"
    return "solid %d air %d changed %s" % [region.solid.size(), region.air.size(), region.changed]
