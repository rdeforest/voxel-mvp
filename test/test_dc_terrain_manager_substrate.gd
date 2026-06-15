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


func test_set_eps_schedules_async_rebuild() -> void:
    # set_eps sets the threshold and schedules an ASYNC rebuild (not a synchronous main-thread remesh —
    # that hitches, and under the budget controller it oscillates). The rebuild is cheap because a
    # stationary change scroll-reuses everything (shift 0). Here we assert the value + the schedule.
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

    mgr._last_center = focus
    mgr.set_eps(4.0)
    assert_eq(mgr.eps_px, 4.0, "set_eps set the threshold")
    assert_eq(mgr._last_center, Vector3.INF, "set_eps scheduled an async rebuild (next tick), no sync hitch")


func test_scroll_rebuild_matches_full_sample() -> void:
    # Stage 2 move path: a SCROLLED rebuild (reuse the previous build's grids, re-sample only the
    # shifted-in shell) must produce the SAME mesh as a fresh FULL-sample rebuild at the new center.
    # The field is static, so a reused overlap cell holds the same world-position sample a fresh fill
    # would take — proving the scroll reuse doesn't corrupt the SDF.
    var store := _store()
    var a := Vector3(0, _surface(0, 0), 0)
    var b := Vector3(20, _surface(20, 0), 0)

    var m1 := DCTerrainManager.new()
    add_child_autofree(m1)
    var f1 := Node3D.new(); add_child_autofree(f1); f1.global_position = a
    m1.setup(f1, store)
    m1._enabled = true
    m1.error_driven = false
    m1._dispatch(a); m1._finish()
    assert_eq(m1._scroll_buffers.size(), DCTerrainManager.LEVELS, "build A filled the scroll buffers")
    m1._dispatch(b); m1._finish()   # scrolled rebuild at B (reuses A's overlap)
    var scrolled: PackedVector3Array = m1._cache.arrays[Mesh.ARRAY_VERTEX]

    var m2 := DCTerrainManager.new()
    add_child_autofree(m2)
    var f2 := Node3D.new(); add_child_autofree(f2); f2.global_position = b
    m2.setup(f2, store)
    m2._enabled = true
    m2.error_driven = false
    m2._dispatch(b); m2._finish()   # full sample at B (no prev)
    var fresh: PackedVector3Array = m2._cache.arrays[Mesh.ARRAY_VERTEX]

    assert_eq(scrolled, fresh, "scrolled rebuild equals a full-sample rebuild at the new center")


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
