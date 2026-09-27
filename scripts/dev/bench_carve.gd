extends SceneTree

# EditStore.predict_carve on the game's field: solve time, sweeps, and whether writing the solved
# lattice empties exactly the plan. Plans: terrain spheres r=3 / r=5 under the surface, a lone
# buried cell, a buried 9^3 block, and a small near-surface sphere where the box rewrite alone flips
# unplanned cells.
#   bin/godot --path . --headless -s scripts/dev/bench_carve.gd


# The autoloads (CellFlips needs the event bus) aren't loaded in a -s script, so this measures
# the write with write_region_flips directly rather than through StoreWrite.
func _initialize() -> void:
    var surface := _surface(0.0, 0.0)

    _run("sphere r=3", _sphere(Vector3(0.5, surface - 3.0, 0.5), 3.0))
    _run("sphere r=5", _sphere(Vector3(0.5, surface - 3.0, 0.5), 5.0))
    _run("lone buried cell", [Vector3i(0, int(surface) - 20, 0)])
    _run("block 9^3", _block(Vector3i(-4, int(surface) - 16, -4), 9))

    var top := _surface(15.0, -16.0)
    _run("near-surface r=1.4", _sphere(Vector3(15.5, top, -15.5), 1.4))

    for n in [2, 3, 4, 5, 7]:
        _run("checker %d^3" % n, _checker(Vector3i(0, int(surface) - 20, 0), n))

    var slab := []
    for x in 27:
        for z in 27:
            slab.append(Vector3i(x - 13, int(surface) - 12, z - 13))
    _run("slab 27x1x27", slab)
    _run("sphere r=5.6 (750)", _sphere(Vector3(0.5, surface - 8.0, 0.5), 5.6))

    var wall_cell := Vector3i(0, int(surface) - 20, 0)
    _run("wall, margin<=1", [wall_cell], _walled(wall_cell), 1)
    _run("wall", [wall_cell], _walled(wall_cell))

    quit()


# A sharp solid face at x = cell.x, the face cells' outer corners at +5: the cell at x = cell.x - 1
# reads solid only while its inner corners stay low, which a 1-cell margin's held face can't offset.
func _walled(cell: Vector3i) -> Callable:
    return func(store: EditStore) -> void:
        var dim := 10
        var origin := Vector3(cell - Vector3i(4, 4, 4))
        var sdf := PackedFloat32Array()
        sdf.resize(dim * dim * dim)
        for z in dim:
            for y in dim:
                for x in dim:
                    sdf[x + dim * (y + dim * z)] = 5.0 if int(origin.x) + x < cell.x else -5.5
        store.write_region(sdf, PackedByteArray(), dim, origin, 1.0)


func _checker(lo: Vector3i, n: int) -> Array:
    return _block(lo, n).filter(func(c: Vector3i) -> bool: return (c.x + c.y + c.z) % 2 == 0)


func _surface(x: float, z: float) -> float:
    return EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


func _fresh() -> EditStore:
    var m := EditStoreManager.new()
    m.setup()
    return m.store


func _sphere(center: Vector3, radius: float) -> Array:
    var store := _fresh()
    var out := []
    for cell in VoxelUtils.cells_in_sphere(center, radius):
        if TerrainProbe.is_solid(store, cell):
            out.append(cell)
    return out


func _block(lo: Vector3i, n: int) -> Array:
    var out := []
    for x in n:
        for y in n:
            for z in n:
                out.append(lo + Vector3i(x, y, z))
    return out


func _run(label: String, plan: Array, prepare := Callable(), max_margin := 0) -> void:
    var store := _fresh()
    if prepare.is_valid():
        prepare.call(store)
    var cells: Array[Vector3i] = []
    cells.assign(plan)

    var t0 := Time.get_ticks_usec()
    var d  := store.predict_carve(cells, max_margin) if max_margin > 0 else store.predict_carve(cells)
    var ms := (Time.get_ticks_usec() - t0) / 1000.0

    if not d.has("sdf"):
        print("%-20s plan %4d  REFUSED proven=%s conflict=%s margin=%d sweeps=%d  %.1f ms"
            % [label, cells.size(), d.proven, d.conflict, d.margin, d.sweeps, ms])
        return

    var was_solid := cells.filter(func(c: Vector3i) -> bool: return TerrainProbe.is_solid(store, c)).size()
    var lo    := Vector3i(d.origin)
    var flips := store.write_region_flips(d.sdf, store.fill_indices_region(lo, d.dim, 1.0), d.dim, d.origin, 1.0)
    var planned := {}
    for c in cells:
        planned[c] = true
    var stray: Array = flips.air.filter(func(c: Vector3i) -> bool: return not planned.has(c))
    var worst := INF
    for c in cells:
        worst = minf(worst, TerrainProbe.sdf(store, c))
    print("   was solid %d, least planned sdf after %.5f" % [was_solid, worst])
    print("%-20s plan %4d  emptied %4d  stray-air %d  went-solid %d  dim %d  margin %d  sweeps %d  %.1f ms"
        % [label, cells.size(), flips.air.size(), stray.size(), flips.solid.size(),
            d.dim, d.margin, d.sweeps, ms])
