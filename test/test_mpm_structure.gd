extends GutTest

# MpmStructure (replace-PBD increment A): the thaw → simulate → freeze loop on REAL terrain.
# Headless: thaw a sphere of solid terrain into MPM (carve + seed particles), simulate until it
# settles, and freeze it back into the store as terrain. This is the loop `mpmthaw` drives in-game.

func _surface() -> int:
    var s := SparseVoxelOctree.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
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

    assert_eq(fv._visited.size(), 125, "flooded every connected solid cell (5³) then stopped")
    assert_gt(fv._reached, 0, "coloured the visible surface cells")
    assert_false(fv._running, "the flood settled (frontier drained), didn't run forever")


# (The scalar-support auto-trigger was removed — it cascaded + locked up. The replacement is an
# async bounded flood-to-ground detachment, scouted by `floodviz` above; its test lands with it.)
