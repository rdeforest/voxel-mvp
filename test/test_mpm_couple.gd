extends GutTest

# MPM thaw/freeze coupling (doc 12) — the one remaining research risk: moving material between
# the simulated particle representation and the static EditStore field. This pins the FREEZE
# direction (particles -> SDF + material). THAW + the crack-free seam against static terrain
# join as later increments.

const WOOD := 4   # MaterialPalette index
const STONE := 1


# A store with no edits (pure generator) + a cube of MPM particles placed in the air well above
# the terrain surface (so the generator is air there and the rasterised result is isolated).
func _air_top() -> int:
    var surface := SparseVoxelOctree.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    return int(surface) + 40


func test_freeze_rasterises_a_particle_cube_into_the_store() -> void:
    var top := _air_top()
    var sim := MpmSim.new()
    sim.configure(Vector3(-16, -16, -16), 32, 1.0, Vector3(0, -9.8, 0), -1000.0)
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
    sim.configure(Vector3(-16, -16, -16), 32, 1.0, Vector3(0, -9.8, 0), -1000.0)
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


# Regression: the freeze is a DEPOSIT — it must union with the field, never erase the terrain its
# bounding box spans. The old code wrote a dense air-default box, so any existing solid the cloud
# didn't occupy was overwritten to air — a cloud-sized cube carved out of the mountain around the
# settled chunk. Here a stone slab sits beside (not under) a small wood cloud, inside the freeze's
# written region but away from any particle. After the freeze it must still be solid stone.
func test_freeze_preserves_surrounding_terrain() -> void:
    var top := _air_top()
    var sim := MpmSim.new()
    sim.configure(Vector3(-16, -16, -16), 32, 1.0, Vector3(0, -9.8, 0), -1000.0)
    for cz in range(-2, 2):
        for cy in range(top, top + 2):
            for cx in range(-2, 2):
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            sim.add_particle(Vector3(cx + ox, cy + oy, cz + oz), 50.0, 0.125)

    var store := EditStoreManager.new()
    store.setup()
    # A stone slab beside the cloud's +X face (x in [3,5)), well inside the freeze's written region
    # but ~1.5 cells past the nearest particle — the bug would erase it.
    store.store.stamp_box(Vector3(4, top + 1, 0), Vector3(2, 2, 2), 0, STONE, 1.0)
    var beside := Vector3(4.0, top + 1.0, 0.0)
    assert_lt(store.store.sample(beside), 0.0, "stone slab is solid before the freeze")

    sim.rasterize_to_store(store.store, 1.0, 0.6, WOOD)

    assert_lt(store.store.sample(beside), 0.0, "surrounding stone is STILL solid after the freeze (not erased)")
    assert_eq(store.store.material_at(beside), STONE, "surrounding terrain keeps its own material (Stone)")
    # And the wood cloud still froze in solid with its own material.
    assert_lt(store.store.sample(Vector3(0.0, top + 1.0, 0.0)), 0.0, "the wood cloud froze solid")
    assert_eq(store.store.material_at(Vector3(0.0, top + 1.0, 0.0)), WOOD, "the cloud kept its Wood material")


func test_thaw_then_freeze_round_trips_a_box() -> void:
    # The fidelity test of the coupling (the information-loss question): a solid box in one store,
    # THAWED to particles and FROZEN back, must reproduce the same solid region in a second store.
    var top := _air_top()
    var src := EditStoreManager.new()
    src.setup()
    src.store.stamp_box(Vector3(0, top + 2, 0), Vector3(4, 4, 4), 0, WOOD, 1.0) # solid box: x,z[-2,2], y[top,top+4]

    var sim := MpmSim.new()
    sim.configure(Vector3(-16, -16, -16), 32, 1.0, Vector3(0, -9.8, 0), -1000.0)
    var n := sim.thaw_from_store(src.store, Vector3(-4, top - 2, -4), 12, 1.0, 2, 50.0, 0.125)
    assert_gt(n, 0, "thaw seeded particles from the solid box")

    var dst := EditStoreManager.new()
    dst.setup()
    sim.rasterize_to_store(dst.store, 1.0, 0.6, WOOD)

    # Both stores must AGREE on solid/air across a set of probe points (the round-trip reproduces
    # the box within the rasteriser's ~1-cell resolution).
    var inside := [Vector3(0, top + 2, 0), Vector3(1.5, top + 1, 1.5), Vector3(-1.5, top + 3, -1.5)]
    var outside := [Vector3(0, top + 10, 0), Vector3(6, top + 2, 0), Vector3(0, top - 4, 0)]
    for p in inside:
        assert_lt(src.store.sample(p), 0.0, "source solid at %s" % p)
        assert_lt(dst.store.sample(p), 0.0, "round-tripped solid at %s" % p)
    for p in outside:
        assert_gt(dst.store.sample(p), 0.0, "round-tripped air at %s" % p)
    assert_eq(dst.store.material_at(Vector3(0, top + 2, 0)), WOOD, "material survives the round-trip")
