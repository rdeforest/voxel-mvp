extends GutTest

# MpmStructure (replace-PBD increment A): the thaw → simulate → freeze loop on REAL terrain.
# Headless: thaw a sphere of solid terrain into MPM (carve + seed particles), simulate until it
# settles, and freeze it back into the store as terrain. This is the loop `mpmthaw` drives in-game.

const MatterLog := preload("res://test/support/matter_log.gd")

const THAWER := EditSource.Kind.INSTRUMENT   # these thaws stand in for `mpmthaw`

var _log: MatterLog


func before_each() -> void:
    _log = MatterLog.new()


func after_each() -> void:
    _log = null


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
    var n := ms.thaw_sphere(center, 3.0, THAWER)
    assert_gt(n, 0, "thawed solid terrain cells into MPM")
    assert_gt(ms.active_count(), 0, "seeded particles (8 per thawed cell)")
    assert_gt(store.store.sample(center), 0.0, "the thawed centre carved to air in the store")

    # --- simulate until it settles and freezes back ---
    _log.clear()
    var froze := false
    for _i in 1500:
        ms.tick(1.0 / 60.0)
        if ms.active_count() == 0:
            froze = true
            break
    assert_true(froze, "the material settled and froze back (particles cleared)")
    while not ms._pending_chunks.is_empty():
        ms.tick(1.0 / 60.0)
    assert_false(_log.events.is_empty(), "the freeze announced its write")
    assert_true(_log.sources().all(func(s: EditSource.Kind) -> bool: return s == EditSource.Kind.MPM),
        "credited to MPM, which the scout ignores")

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
    ms.thaw_cells(cells, THAWER)

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


# Provenance: docs/bugs/mpm-thaw-carve-leaves-planned-cells.md (filed from the fix for the since-
# deleted mpm-thaw-events-unmeasured). On the game's field at this spot, a radius-1.4 thaw
# plans cells that the carve can't empty (their corners are shared with kept terrain), and
# rewriting the box re-encodes the generated field so a cell the plan never named reads air
# afterwards. The event's flips (and the particles) must name exactly the cells that went air.
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
    var n   := ms.thaw_sphere(center, 1.4, THAWER)
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

    assert_eq(_sorted(_log.air), _sorted(went_air), "the event's air flips are exactly the cells that went air")
    assert_eq(_sorted(_log.solid), _sorted(went_solid), "its solid flips are exactly the cells that went solid")
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

    assert_eq(ms.thaw_cells([cell], THAWER), 0, "no cell thawed")
    assert_true(TerrainProbe.is_solid(store.store, cell), "the cell is still solid terrain")
    assert_eq(_log.air.size(), 0, "no air flip for a cell that did not go air")
    assert_eq(ms.active_count(), 0, "no particles duplicate matter still in the store")


# DetachmentScout tells its own carve from anyone else's by the source the event carries, so a thaw
# is announced once, credited to whoever asked for it.
func test_thaw_is_announced_once_with_its_source() -> void:
    var store := EditStoreManager.new()
    store.setup()

    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(store.store)

    var spots := {EditSource.Kind.SCOUT: Vector2(0.5, 0.5), EditSource.Kind.INSTRUMENT: Vector2(20.5, 0.5)}
    for source: EditSource.Kind in spots:
        var at: Vector2 = spots[source]
        var top := EditStore.terrain_surface(at.x, at.y, EditStoreManager.BASE, EditStoreManager.AMP,
            EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
        _log.clear()
        var n := ms.thaw_sphere(Vector3(at.x, top - 3.0, at.y), 3.0, source)
        assert_gt(n, 0, "precondition: the thaw empties cells")
        assert_eq(_log.sources(), [source] as Array[EditSource.Kind], "one event, credited to its source")


# A second thaw of the same sphere plans the cells the first couldn't empty, but its rewrite
# repeats the first's values: no change, so no re-mesh event (with MPM idle it would re-seed the
# scout onto the same piece).
func test_thaw_that_changes_nothing_announces_no_edit() -> void:
    var store := EditStoreManager.new()
    store.setup()
    var center := Vector3(0.5, _surface() - 3.0, 0.5)

    var first: MpmStructure = autofree(MpmStructure.new())
    first.setup(store.store)
    first.thaw_sphere(center, 3.0, THAWER)

    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(store.store)

    var replan := ms._carve_corners(ms._plan_thaw(VoxelUtils.cells_in_sphere(center, 3.0)))
    assert_false(replan.is_empty(), "precondition: the repeat still rewrites corners")

    _log.clear()
    var n := ms.thaw_sphere(center, 3.0, THAWER)

    assert_eq(n, 0, "precondition: the repeat empties nothing")
    assert_eq(_log.events.size(), 0, "a rewrite that changed nothing announces no edit")


# (Drafted by Claude, overnight 2026-09-27.) A large freeze is announced chunk by chunk, and the
# order is the order structural subscribers hear it in, so it can't depend on where the camera is:
# a replayed recording has a different camera (or none) and must see the same events.
func test_freeze_announcement_order_ignores_the_camera() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    var ms: MpmStructure = autofree(MpmStructure.new())
    add_child(ms)
    ms.setup(manager.store)
    var cam: Camera3D = autofree(Camera3D.new())
    add_child(cam)
    cam.make_current()

    var origin := Vector3(0, 40, 0)
    var dim    := 3 * MpmStructure.CHUNK
    var orders: Array = []
    for eye in [origin, origin + Vector3.ONE * float(dim)]:
        cam.global_position = eye
        assert_eq(get_viewport().get_camera_3d(), cam, "precondition: the camera MpmStructure would see")
        _log.clear()
        ms._queue_freeze_chunks(origin, dim)
        while not ms._pending_chunks.is_empty():
            ms.tick(1.0 / 60.0)
        orders.append(_log.events.map(func(e: TerrainSdfChangedEvent) -> Vector3: return e.box_origin))

    assert_eq(orders[0].size(), 27, "precondition: a 3x3x3-chunk region")
    assert_eq(orders[1], orders[0], "the same announcements in the same order from either corner")
    var heights: Array = orders[0].map(func(o: Vector3) -> float: return o.y)
    var sorted := heights.duplicate()
    sorted.sort()
    assert_eq(heights, sorted, "bottom layer first")


# (Drafted by Claude, overnight 2026-09-27.) A second freeze landing while the first is still being
# announced must not drop the first one's remaining chunks: those announcements are what register
# the frozen pile with support.
func test_a_freeze_during_announcement_keeps_the_earlier_chunks() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(manager.store)
    var dim := 3 * MpmStructure.CHUNK

    ms._queue_freeze_chunks(Vector3(0, 40, 0), dim)
    ms.tick(1.0 / 60.0)
    ms._queue_freeze_chunks(Vector3(100, 40, 0), dim)
    while not ms._pending_chunks.is_empty():
        ms.tick(1.0 / 60.0)

    assert_eq(_log.events.size(), 54, "all 27 chunks of each freeze were announced")
