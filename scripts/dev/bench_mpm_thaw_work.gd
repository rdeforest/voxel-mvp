extends RefCounted

# Times MpmStructure.thaw_cells on a terrain sphere and on a floating block (a detachment).


static func run() -> void:
    for radius in [3.0, 5.0]:
        var mgr := EditStoreManager.new()
        mgr.setup()
        var top := EditStore.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
            EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
        var ms := MpmStructure.new()
        ms.setup(mgr.store)
        var t0 := Time.get_ticks_usec()
        var n := ms.thaw_sphere(Vector3(0.5, top - 3.0, 0.5), radius)
        print("sphere r ", radius, " thawed ", n, " usec ", Time.get_ticks_usec() - t0)
        ms.free()
    var block_mgr := EditStoreManager.new()
    block_mgr.setup()
    var base := int(EditStore.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)) + 30
    block_mgr.store.stamp_box(Vector3(0.5, float(base) + 5.5, 0.5), Vector3(10, 10, 10), 0, 1, 1.0)
    var cells: Array[Vector3i] = []
    for z in range(-7, 8):
        for y in range(base - 2, base + 14):
            for x in range(-7, 8):
                if TerrainProbe.is_solid(block_mgr.store, Vector3i(x, y, z)):
                    cells.append(Vector3i(x, y, z))
    var block_ms := MpmStructure.new()
    block_ms.setup(block_mgr.store)
    var block_t0 := Time.get_ticks_usec()
    var block_n := block_ms.thaw_cells(cells)
    print("block cells ", cells.size(), " thawed ", block_n, " usec ", Time.get_ticks_usec() - block_t0)
    block_ms.free()
