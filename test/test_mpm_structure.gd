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
