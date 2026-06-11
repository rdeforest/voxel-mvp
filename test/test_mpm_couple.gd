extends GutTest

# MPM thaw/freeze coupling (doc 12) — the one remaining research risk: moving material between
# the simulated particle representation and the static EditStore field. This pins the FREEZE
# direction (particles -> SDF + material). THAW + the crack-free seam against static terrain
# join as later increments.

const WOOD := 4   # MaterialPalette index


# A store with no edits (pure generator) + a cube of MPM particles placed in the air well above
# the terrain surface (so the generator is air there and the rasterised result is isolated).
func _air_top() -> int:
    var surface := SparseVoxelOctree.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    return int(surface) + 40


func test_freeze_rasterises_a_particle_cube_into_the_store() -> void:
    var top := _air_top()
    var sim := MpmSim.new()
    sim.configure(Vector3(-16, -16, -16), 32, 1.0, Vector3(0, -9.8, 0), 5000.0, 0.2, -1000.0)
    # A solid 4x2x4 cube of particles (8 per cell) centred on the air region.
    for cz in range(-2, 2):
        for cy in range(top, top + 2):
            for cx in range(-2, 2):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), 50.0, 0.125)

    var store := EditStoreManager.new()
    store.setup()
    assert_eq(store.store.leaf_count(), 0, "store starts as pure generator (no edits)")

    var region := sim.rasterize_to_store(store.store, 1.0, 0.6, WOOD)
    assert_false(region.is_empty(), "the freeze wrote a region")
    assert_gt(store.store.leaf_count(), 0, "the freeze created edits in the store")

    # Inside the cloud -> solid; the cube's material is carried.
    var inside := Vector3(0.0, top + 1.0, 0.0)
    assert_lt(store.store.sample(inside), 0.0, "a point inside the particle cloud reads solid")
    assert_eq(store.store.material_at(inside), WOOD, "the frozen material is the cube's (Wood)")

    # Well outside the cloud but inside the written region -> air (the generator is air up here).
    assert_gt(store.store.sample(Vector3(0.0, top + 6.0, 0.0)), 0.0, "a point above the cloud reads air")
    assert_gt(store.store.sample(Vector3(8.0, top + 1.0, 0.0)), 0.0, "a point beside the cloud reads air")


func test_frozen_surface_tracks_the_cloud_extent() -> void:
    # The solid/air boundary should sit ~at the cloud's edge (within the sphere radius), not far
    # beyond it — the freeze reproduces the cloud's shape, not a bloated blob.
    var top := _air_top()
    var sim := MpmSim.new()
    sim.configure(Vector3(-16, -16, -16), 32, 1.0, Vector3(0, -9.8, 0), 5000.0, 0.2, -1000.0)
    for cz in range(-2, 2):
        for cy in range(top, top + 2):
            for cx in range(-2, 2):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), 50.0, 0.125)
    var store := EditStoreManager.new()
    store.setup()
    sim.rasterize_to_store(store.store, 1.0, 0.6, WOOD)

    # The cube spans x in [-2, 2). A point just inside the +X face is solid; ~2 cells past it air.
    assert_lt(store.store.sample(Vector3(1.5, top + 1.0, 0.0)), 0.0, "just inside the +X edge is solid")
    assert_gt(store.store.sample(Vector3(3.5, top + 1.0, 0.0)), 0.0, "2 cells past the +X edge is air (not a bloated blob)")
