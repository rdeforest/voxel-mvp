extends GutTest

# FIX 2 — edits during an in-flight full re-mesh must neither block visual feedback nor be lost.
# These pin the SCHEDULING logic in DCTerrainManager (the splice mechanics themselves are covered by
# test_dc_incremental_splice):
#   - a during-job edit that can't splice sets _dirty_during_job (deferred), NOT _last_center
#     (can't dispatch while a job runs);
#   - an idle edit that can't splice forces a full re-mesh (_last_center = INF) as before;
#   - the pending queue is bounded — an overflow coalesces to one full re-mesh;
#   - _reapply_pending_edits clears the queue and, for a no-longer-spliceable box, forces one
#     full re-mesh.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

func _store() -> EditStore:
    var es := EditStore.new()
    es.setup(Vector3(-256, -256, -256), 512.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return es

func _mgr() -> DCTerrainManager:
    var m := DCTerrainManager.new()
    add_child_autofree(m)
    var follow := Node3D.new()
    add_child_autofree(follow)
    m.setup(follow, _store())
    m._enabled = true
    return m

func _event(origin: Vector3, size: Vector3) -> TerrainSdfChangedEvent:
    return TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, origin, size)


func test_idle_unspliceable_edit_forces_full_remesh():
    # Idle (no job) + can't splice (empty cache) → fall back to a full re-mesh next tick.
    var m := _mgr()
    m._task_id = -1
    m._last_center = Vector3.ZERO
    m._on_terrain_edit(_event(Vector3(8, 8, 8), Vector3.ONE * 6))
    assert_eq(m._last_center, Vector3.INF, "idle + can't splice → full re-mesh queued")
    assert_false(m._dirty_during_job, "no job in flight, so not the deferred path")


func test_unspliceable_edit_during_job_defers_not_dispatches():
    # A job is in flight, so we must NOT force a dispatch (can't — worker busy). Mark dirty instead.
    var m := _mgr()
    m._task_id = 999            # fake in-flight job
    m._last_center = Vector3.ZERO
    m._on_terrain_edit(_event(Vector3(8, 8, 8), Vector3.ONE * 6))
    assert_true(m._dirty_during_job, "during job + can't splice → deferred (dirty)")
    assert_ne(m._last_center, Vector3.INF, "did NOT force a dispatch while the job runs")
    m._task_id = -1             # reset so teardown doesn't touch a fake task


func test_queue_overflow_coalesces():
    var m := _mgr()
    for i in 40:                # > _MAX_PENDING (32)
        m._queue_pending(Vector3(i, 0, 0), Vector3.ONE)
    assert_true(m._dirty_during_job, "overflow coalesces to one full re-mesh")
    assert_lte(m._pending_edits.size(), 32, "queue stayed bounded")


func test_reapply_clears_pending_and_forces_remesh_when_unspliceable():
    var m := _mgr()
    m._cache_arrays = [1]       # non-empty so _splice_box passes its is_empty guard...
    m._cache_origin = Vector3i.ZERO
    m._last_center = Vector3.ZERO
    # ...but this box is far outside the fine core, so _splice_box returns false (never meshes).
    m._pending_edits = [[Vector3(900, 900, 900), Vector3.ONE]]
    m._reapply_pending_edits()
    assert_eq(m._pending_edits.size(), 0, "queue cleared after reapply")
    assert_eq(m._last_center, Vector3.INF, "a no-longer-spliceable pending box forces a full re-mesh")
