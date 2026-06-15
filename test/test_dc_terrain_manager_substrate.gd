extends GutTest

# Guards the DCTerrainManager full-build path (dispatch -> worker -> finish) across the sub-metre
# parameterization. Assertions are in WORLD coordinates (verts through the mesh instance's
# transform), so they hold at any RENDER_BASE_CELL: the rendered terrain must sit around the focus,
# on the terrain surface, regardless of the internal lattice/base-cell scaling. This is the
# behaviour-preserving guard for Stage 0 and the correctness guard for the Stage 1 flip to 0.25.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

func _store() -> EditStore:
    var es := EditStore.new()
    es.setup(Vector3(-512, -512, -512), 1024.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return es

func _surface(x: float, z: float) -> float:
    return SparseVoxelOctree.terrain_surface(x, z, BASE, AMP, PERIOD, OCTAVES, SEED)


func test_full_build_renders_terrain_in_world_space() -> void:
    var focus := Vector3(0, _surface(0, 0), 0)
    var mgr := DCTerrainManager.new()
    add_child_autofree(mgr)
    var follow := Node3D.new()
    add_child_autofree(follow)
    follow.global_position = focus
    mgr.setup(follow, _store())
    mgr._enabled = true
    mgr.error_driven = false   # no Camera3D in the headless test → proj=0 would collapse everything;
                               # uniform build is camera-independent and exercises the same geometry path

    mgr._dispatch(focus)
    mgr._finish()   # blocks on the worker, installs the mesh + cache

    var arrays: Array = mgr._cache.arrays
    assert_false(arrays.is_empty(), "full build produced a cached mesh")
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    assert_gt(verts.size(), 500, "meaningfully tessellated terrain")

    # World transform of the rendered mesh (verts are lattice/base-cell; the instance transform
    # scales + positions them into world). Sample the surface height under the focus and assert the
    # rendered verts near the focus column hug it — proves the world scale/origin are correct.
    var xform := mgr._mesh_instance.global_transform
    var near := 0
    var hugged := 0
    for v in verts:
        var w := xform * v
        if absf(w.x - focus.x) < 6.0 and absf(w.z - focus.z) < 6.0:
            near += 1
            if absf(w.y - _surface(w.x, w.z)) < 4.0:
                hugged += 1
    assert_gt(near, 20, "rendered verts exist in the focus column (correct world position)")
    assert_gt(float(hugged) / float(maxi(near, 1)), 0.8, "those verts hug the terrain surface (correct world scale)")


func test_set_eps_remeshes_in_place_from_retained_octree() -> void:
    # Stage 2c: set_eps re-collapses the RETAINED octree (no worker rebuild) and swaps a valid mesh in.
    # error_driven=false (headless has no camera), so the surface is identical — the path under test is
    # _mesher.remesh() + cache swap, NOT a scheduled full rebuild.
    var focus := Vector3(0, _surface(0, 0), 0)
    var mgr := DCTerrainManager.new()
    add_child_autofree(mgr)
    var follow := Node3D.new()
    add_child_autofree(follow)
    follow.global_position = focus
    mgr.setup(follow, _store())
    mgr._enabled = true
    mgr.error_driven = false
    mgr._dispatch(focus)
    mgr._finish()
    assert_gt((mgr._cache.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 500, "primed a base mesh")

    mgr._last_center = focus      # settled — any later INF would mean a full rebuild was scheduled
    mgr.set_eps(4.0)
    assert_ne(mgr._last_center, Vector3.INF, "set_eps used the in-place remesh, did NOT schedule a full rebuild")
    assert_gt((mgr._cache.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 500, "in-place remesh left a valid cached mesh")


func test_async_splice_applies_an_edit() -> void:
    # Prime a full build, dig into the store, then drive the async splice (dispatch -> worker ->
    # apply) and confirm the cached mesh changed — the edit shows without a full re-mesh.
    var store := _store()
    var focus := Vector3(0, _surface(0, 0), 0)
    var mgr := DCTerrainManager.new()
    add_child_autofree(mgr)
    var follow := Node3D.new()
    add_child_autofree(follow)
    follow.global_position = focus
    mgr.setup(follow, store)
    mgr._enabled = true
    mgr.error_driven = false
    mgr._dispatch(focus)
    mgr._finish()
    var verts_before: int = (mgr._cache.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    assert_gt(verts_before, 500, "primed a base mesh")

    # Carve a hole into the store at the focus, then fire the edit + pump _process until the async
    # splice lands (the worker runs in parallel; is_task_completed flips, _finish_splice applies).
    store.stamp_sphere(focus, 3.0, VoxelConstants.STORE_OP_SUBTRACT, 0, VoxelConstants.RENDER_BASE_CELL)
    mgr._on_terrain_edit(TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, focus - Vector3.ONE * 4.0, Vector3.ONE * 8.0))
    assert_eq(mgr._splice_queue.size(), 1, "the dig queued a splice")
    mgr._process(0.016)   # dispatch the splice to a worker
    assert_ne(mgr._splice_task_id, -1, "the dig dispatched a worker splice (in-core, splice-able)")
    assert_ne(mgr._last_center, Vector3.INF, "did not fall back to a full re-mesh")
    var done := false
    for _i in 3000:       # poll read-only (don't consume the task); let _process apply
        if WorkerThreadPool.is_task_completed(mgr._splice_task_id):
            done = true
            break
        OS.delay_msec(1)  # give the worker real wall-clock time (~100ms mesh)
    assert_true(done, "the worker splice job completed")
    mgr._process(0.016)   # is_task_completed → _finish_splice applies
    assert_eq(mgr._splice_task_id, -1, "the async splice applied")
    var verts_after: int = (mgr._cache.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    assert_ne(verts_after, verts_before, "the spliced dig changed the cached mesh (edit is reflected)")
