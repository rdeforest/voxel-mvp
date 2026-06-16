extends GutTest

# VoxelChunkBody (parts-as-voxels S5): a detached set of cells becomes a RigidBody3D with a
# DC-meshed visual (the chunk's real surface, in material colour) and a box-compound collider.
# Visual *fidelity* needs GPU eyes; headless we pin the structure: a non-empty bounded mesh,
# colliders covering the cells, mass + cell_offsets, and that non-chunk terrain is excluded.

const UNION := 0   # EditStore op: union (adds solid)
const WOOD  := 4   # MaterialPalette index


# A store whose only solid is a `dims`-sized block of cells well above the terrain surface
# (so the generator is air there and the block is the entire local solid). Returns the store
# and the exact cell list.
func _stub_chunk(dims: Vector3i) -> Array:
    var manager := EditStoreManager.new()
    manager.setup()
    var surface := EditStore.terrain_surface(0.0, 0.0, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    var base := Vector3i(0, int(surface) + 40, 0)   # air region above the ground
    var center := Vector3(base) + Vector3(dims) * 0.5
    manager.store.stamp_box(center, Vector3(dims), UNION, WOOD, 1.0)

    var cells: Array[Vector3i] = []
    for z in dims.z:
        for y in dims.y:
            for x in dims.x:
                var cell := base + Vector3i(x, y, z)
                if manager.store.sample(Vector3(cell) + Vector3(0.5, 0.5, 0.5)) < 0.0:
                    cells.append(cell)
    return [manager, cells]


func test_builds_a_rigidbody_with_mesh_and_colliders() -> void:
    var stub := _stub_chunk(Vector3i(4, 2, 4))
    var store: EditStoreManager = stub[0]
    var cells: Array[Vector3i]  = stub[1]
    assert_eq(cells.size(), 32, "the stub block is fully solid (4*2*4 cells)")

    var body: RigidBody3D = autofree(VoxelChunkBody.from_voxels(cells, store.store))
    assert_not_null(body, "a body is produced")
    assert_eq(body.mass, float(cells.size()), "mass is one unit per cell")

    var meshes:    Array = body.get_children().filter(func(c): return c is MeshInstance3D)
    var colliders: Array = body.get_children().filter(func(c): return c is CollisionShape3D)
    assert_eq(meshes.size(), 1, "exactly one visual mesh (the DC chunk), not per-box cubes")
    assert_gt(colliders.size(), 0, "at least one box collider")

    var surfaces: int = (meshes[0] as MeshInstance3D).mesh.get_surface_count()
    assert_gt(surfaces, 0, "the DC mesh has a surface (the chunk isn't invisible)")


func test_cell_offsets_meta_round_trips_to_world_cells() -> void:
    var stub := _stub_chunk(Vector3i(2, 2, 2))
    var store: EditStoreManager = stub[0]
    var cells: Array[Vector3i]  = stub[1]

    var body: RigidBody3D = autofree(VoxelChunkBody.from_voxels(cells, store.store))
    var offsets: Array = body.get_meta("cell_offsets")
    assert_eq(offsets.size(), cells.size(), "one offset per cell (the falling-body classifier reads these)")

    # body.position + offset is each cell's centre, so flooring recovers the original cell.
    var recovered := {}
    for off in offsets:
        recovered[Vector3i((body.position + off).floor())] = true
    for cell in cells:
        assert_true(recovered.has(cell), "offset %s maps back to its source cell" % cell)


func test_mesh_stays_within_the_chunk_bounds() -> void:
    # A 6x2x6 slab (2 m thick = resolvable at the 1 m grid; a 1 m feature is sub-Nyquist,
    # doc 03 #1). The DC mesh must hug the chunk, not bulge into the air apron or pull in
    # surrounding terrain (the component mask excludes everything but the cells).
    var stub := _stub_chunk(Vector3i(6, 2, 6))
    var store: EditStoreManager = stub[0]
    var cells: Array[Vector3i]  = stub[1]

    var body: RigidBody3D = autofree(VoxelChunkBody.from_voxels(cells, store.store))
    var mi: MeshInstance3D = body.get_children().filter(func(c): return c is MeshInstance3D)[0]
    var aabb := mi.get_aabb()                        # local to the mesh instance
    var world_min := mi.position + aabb.position + body.position
    var world_max := world_min + aabb.size

    var lo := Vector3(cells[0])
    var hi := lo
    for c in cells:
        lo = lo.min(Vector3(c))
        hi = hi.max(Vector3(c) + Vector3.ONE)
    # Allow a half-cell of DC vertex placement slack on each side; reject apron-sized bulge.
    assert_gt(world_min.y, lo.y - 1.0, "mesh bottom hugs the slab, not the apron")
    assert_lt(world_max.y, hi.y + 1.0, "mesh top hugs the slab, not the apron")
    assert_gt(world_min.x, lo.x - 1.0, "mesh doesn't bulge past the slab in X")
    assert_lt(world_max.x, hi.x + 1.0, "mesh doesn't bulge past the slab in X")
