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


func test_unsupported_cell_flags_a_fall_candidate_and_thaws() -> void:
    # The auto-trigger (replace-PBD B): a genuinely unsupported tracked cell is flagged by the
    # support analysis and thaws into the MPM substrate (what `physics_mode mpm` wires up).
    var store := EditStoreManager.new()
    store.setup()
    var base := _surface() + 30                    # a 3³ solid block floating in the air
    store.store.stamp_box(Vector3(0.5, float(base) + 1.5, 0.5), Vector3(3, 3, 3), 0, 1, 1.0)
    var cell := Vector3i(0, base, 0)               # the block's BOTTOM cell — air below it, unsupported
    assert_lt(store.store.sample(Vector3(cell) + Vector3(0.5, 0.5, 0.5)), 0.0, "the bottom cell is solid")

    var ts := TerrainSupport.new()
    ts.store = store.store
    ts._register_voxel(cell, Materials.STONE)
    var guard := 0
    while not ts.dirty_queue.is_empty() and guard < 1000:
        ts.process_dirty_queue()
        guard += 1
    assert_false(ts.fall_candidates.is_empty(), "the unsupported cell is flagged as a fall candidate")

    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(store.store)
    var thawed := ms.thaw_cells(ts.take_fall_candidates())
    assert_gt(thawed, 0, "the fall candidate thawed into MPM")
    assert_gt(ms.active_count(), 0, "particles seeded from the unsupported cell")
    assert_eq(ts.voxel_data.size(), 0, "the thawed cell left the tracked set — it's MPM now, not static terrain")
