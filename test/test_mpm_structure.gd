extends GutTest

# MpmStructure (replace-PBD increment A): the thaw → simulate → freeze loop on REAL terrain.
# Headless: thaw a sphere of solid terrain into MPM (carve + seed particles), simulate until it
# settles, and freeze it back into the store as terrain. This is the loop `mpmthaw` drives in-game.

var _added:   Array[Vector3i] = []
var _removed: Array[Vector3i] = []
var _edits:   Array[int]      = []   # the watched MPM's active_count as each TerrainSdfChanged arrives

var _watched: MpmStructure


func before_each() -> void:
    _added.clear()
    _removed.clear()
    _edits.clear()
    _watched = null
    VoxelEventBusSingleton.subscribe(VoxelAddedEvent.CHANNEL,        _on_added)
    VoxelEventBusSingleton.subscribe(VoxelRemovedEvent.CHANNEL,      _on_removed)
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_edit)


func after_each() -> void:
    VoxelEventBusSingleton.unsubscribe(VoxelAddedEvent.CHANNEL,        _on_added)
    VoxelEventBusSingleton.unsubscribe(VoxelRemovedEvent.CHANNEL,      _on_removed)
    VoxelEventBusSingleton.unsubscribe(TerrainSdfChangedEvent.CHANNEL, _on_edit)


func _on_added(e: VoxelAddedEvent) -> void:
    _added.append(e.pos)


func _on_removed(e: VoxelRemovedEvent) -> void:
    _removed.append(e.pos)


func _on_edit(_e: TerrainSdfChangedEvent) -> void:
    if _watched != null:
        _edits.append(_watched.active_count())


func _surface() -> int:
    var s := EditStore.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    return int(s)


func test_thaw_simulate_freeze_loop_on_real_terrain() -> void:
    var store := EditStoreManager.new()
    store.setup()
    var top := _surface()
    var center := Vector3(0.5, float(top) - 3.0, 0.5)   # solid, just under the surface

    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(store.store)

    # --- thaw: real terrain carves out + becomes particles ---
    assert_lt(store.store.sample(center), 0.0, "the thaw centre is solid terrain to begin with")
    var n := ms.thaw_sphere(center, 3.0)
    assert_gt(n, 0, "thawed solid terrain cells into MPM")
    assert_gt(ms.active_count(), 0, "seeded particles (8 per thawed cell)")
    assert_gt(store.store.sample(center), 0.0, "the thawed centre carved to air in the store")

    # --- simulate until it settles and freezes back ---
    var froze := false
    for _i in 1500:
        ms.tick(1.0 / 60.0)
        if ms.active_count() == 0:
            froze = true
            break
    assert_true(froze, "the material settled and froze back (particles cleared)")

    # --- freeze: re-solidified into terrain near the rest location (at/below the thaw) ---
    var solid_found := false
    for dy in range(-5, 1):
        if store.store.sample(center + Vector3(0, dy, 0)) < 0.0:
            solid_found = true
            break
    assert_true(solid_found, "the frozen material re-entered the store as solid terrain")


# A free-standing solid block (surrounded by air) thawed in full must clear COMPLETELY — no
# leftover surface shell. The old carve raised only each cell's base (min) corner, so the
# +X/+Y/+Z face cells kept solid far corners — a 1..7/8-solid crust the probe found. The corner-
# field carve raises a corner unless a kept-solid cell needs it, so an all-air-surrounded block
# clears to nothing.
func test_thaw_leaves_no_solid_shell() -> void:
    var store := EditStoreManager.new()
    store.setup()
    var base := _surface() + 30   # well above terrain — air on every side
    store.store.stamp_box(Vector3(0.5, float(base) + 2.5, 0.5), Vector3(4, 4, 4), 0, 1, 1.0)

    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(store.store)

    # Collect the block's solid cells and thaw them all (no stepping — we check the carve itself).
    var cells: Array[Vector3i] = []
    for z in range(-4, 5):
        for y in range(base - 2, base + 8):
            for x in range(-4, 5):
                if store.store.sample(Vector3(x + 0.5, y + 0.5, z + 0.5)) < VoxelConstants.SDF_SOLID_THRESHOLD:
                    cells.append(Vector3i(x, y, z))
    assert_gt(cells.size(), 0, "the block has solid cells to thaw")
    ms.thaw_cells(cells)

    # Every grid corner in/around the block must now be air — nothing left behind.
    var solid_corners := 0
    for z in range(-5, 6):
        for y in range(base - 3, base + 9):
            for x in range(-5, 6):
                if store.store.sample(Vector3(x, y, z)) < VoxelConstants.SDF_SOLID_THRESHOLD:
                    solid_corners += 1
    assert_eq(solid_corners, 0, "the thawed block cleared completely — no solid shell left behind")


func test_floodviz_reaches_a_connected_block_and_settles() -> void:
    # The flood scout: from a seed cell it should reach every connected solid cell and then stop
    # (frontier empty), colouring the visible surface cells. A floating 5³ block = 125 cells.
    var store := EditStoreManager.new()
    store.setup()
    var base := _surface() + 30
    store.store.stamp_box(Vector3(0.5, float(base) + 2.5, 0.5), Vector3(5, 5, 5), 0, 1, 1.0)

    var fv: FloodViz = autofree(FloodViz.new())
    fv.setup(store.store)
    fv.start(Vector3i(0, base + 2, 0), 1000) # seed the block centre
    for _i in 50:
        fv._process(0.0)

    assert_eq(fv._flood.visited.size(), 125, "flooded every connected solid cell (5³) then stopped")
    assert_gt(fv._reached, 0, "coloured the visible surface cells")
    assert_false(fv._running, "the flood settled (frontier drained), didn't run forever")


# (The scalar-support auto-trigger was removed — it cascaded + locked up. The replacement is an
# async bounded flood-to-ground detachment, scouted by `floodviz` above; its test lands with it.)


# Cell -> solid at its sample point, over a cube of cells around `around`: the truth the thaw's
# events are checked against, measured independently of the code under test.
func _solidity(store: EditStore, around: Vector3i, reach: int) -> Dictionary:
    var out := {}

    for z in range(-reach, reach + 1):
        for y in range(-reach, reach + 1):
            for x in range(-reach, reach + 1):
                var cell := around + Vector3i(x, y, z)
                out[cell] = TerrainProbe.is_solid(store, cell)

    return out


func _sorted(cells: Array[Vector3i]) -> Array[Vector3i]:
    var out := cells.duplicate()
    out.sort()
    return out


# docs/bugs/mpm-thaw-events-unmeasured.md. On the game's field at this spot, a radius-1.4 thaw
# plans cells that the carve can't empty (their corners are shared with kept terrain), and
# rewriting the box re-encodes the generated field so a cell the plan never named reads air
# afterwards. voxel_removed (and the particles) must name exactly the cells that went air.
func test_thaw_events_are_the_measured_flips() -> void:
    var store := EditStoreManager.new()
    store.setup()
    var top := EditStore.terrain_surface(15.0, -16.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    var center := Vector3(15.5, top, -15.5)
    var around := Vector3i(center.floor())

    var planned := {}
    for cell in VoxelUtils.cells_in_sphere(center, 1.4):
        if TerrainProbe.is_solid(store.store, cell):
            planned[cell] = true

    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(store.store)

    var was := _solidity(store.store, around, 10)
    var n   := ms.thaw_sphere(center, 1.4)
    var now := _solidity(store.store, around, 10)

    var went_air:   Array[Vector3i] = []
    var went_solid: Array[Vector3i] = []
    for cell: Vector3i in was:
        if was[cell] and not now[cell]:
            went_air.append(cell)
        elif now[cell] and not was[cell]:
            went_solid.append(cell)

    assert_true(went_air.any(func(c: Vector3i) -> bool: return not planned.has(c)),
        "precondition: the thaw flips a cell outside its plan to air")
    assert_true(planned.keys().any(func(c: Vector3i) -> bool: return not went_air.has(c)),
        "precondition: a planned cell survives the carve")

    assert_eq(_sorted(_removed), _sorted(went_air), "voxel_removed names exactly the cells that went air")
    assert_eq(_sorted(_added), _sorted(went_solid), "voxel_added names exactly the cells that went solid")
    assert_eq(n, went_air.size(), "the thaw count is the cells emptied")
    assert_eq(ms.active_count(), 8 * went_air.size(), "particles are seeded only for the cells emptied")


# A lone cell deep in the ground has every corner shared with kept solid, so the carve can clear
# none of them: nothing leaves the store, so nothing may be reported or enter the sim.
func test_thaw_of_an_enclosed_cell_moves_nothing() -> void:
    var store := EditStoreManager.new()
    store.setup()
    var cell := Vector3i(0, _surface() - 20, 0)
    assert_true(_solidity(store.store, cell, 1).values().all(func(v: bool) -> bool: return v),
        "precondition: the cell and all 26 neighbours are solid, so no corner of it may clear")

    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(store.store)

    assert_eq(ms.thaw_cells([cell]), 0, "no cell thawed")
    assert_true(TerrainProbe.is_solid(store.store, cell), "the cell is still solid terrain")
    assert_eq(_removed.size(), 0, "no voxel_removed for a cell that did not go air")
    assert_eq(ms.active_count(), 0, "no particles duplicate matter still in the store")


# DetachmentScout tells MPM's own carve from a player's edit by MPM being active when the edit's
# TerrainSdfChanged arrives, so the particles must already be in the sim by then.
func test_thaw_is_active_when_its_edit_is_announced() -> void:
    var store := EditStoreManager.new()
    store.setup()

    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(store.store)

    _watched = ms
    var n := ms.thaw_sphere(Vector3(0.5, _surface() - 3.0, 0.5), 3.0)

    assert_gt(n, 0, "precondition: the thaw empties cells")
    assert_eq(_edits, [8 * n] as Array[int], "one TerrainSdfChanged, with every particle already in the sim")


# A second thaw of the same sphere plans the cells the first couldn't empty, but its rewrite
# repeats the first's values: no change, so no re-mesh event (with MPM idle it would re-seed the
# scout onto the same piece).
func test_thaw_that_changes_nothing_announces_no_edit() -> void:
    var store := EditStoreManager.new()
    store.setup()
    var center := Vector3(0.5, _surface() - 3.0, 0.5)

    var first: MpmStructure = autofree(MpmStructure.new())
    first.setup(store.store)
    first.thaw_sphere(center, 3.0)

    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(store.store)

    var replan := ms._carve_corners(ms._plan_thaw(VoxelUtils.cells_in_sphere(center, 3.0)))
    assert_false(replan.is_empty(), "precondition: the repeat still rewrites corners")

    _watched = ms
    var n := ms.thaw_sphere(center, 3.0)

    assert_eq(n, 0, "precondition: the repeat empties nothing")
    assert_eq(_edits.size(), 0, "a rewrite that changed nothing announces no edit")
