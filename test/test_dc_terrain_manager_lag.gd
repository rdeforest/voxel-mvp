extends GutTest

# Async edit-splice scheduling in DCTerrainManager. At sub-metre a patch mesh is ~100ms, too slow
# for the main thread, so edits queue and mesh on a worker (the splice mechanics themselves are
# covered by test_dc_incremental_splice). These pin the queue/decision logic:
#   - an edit enqueues a splice (doesn't mesh synchronously);
#   - the queue is bounded — an overflow coalesces to one full re-mesh;
#   - edits seen during a full build are recorded for re-queue on finish;
#   - a dispatch for an out-of-core / over-size box falls back to a full re-mesh (no worker task).

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


func test_edit_enqueues_a_splice():
    var m := _mgr()
    m._task_id = -1
    m._on_terrain_edit(_event(Vector3(8, 8, 8), Vector3.ONE * 6))
    assert_eq(m._splice_queue.size(), 1, "the edit queued an async splice (no synchronous mesh)")
    assert_eq(m._splice_task_id, -1, "no worker dispatched yet (that happens in _process)")


func test_queue_overflow_forces_full_remesh():
    var m := _mgr()
    m._last_center = Vector3.ZERO
    for i in m._MAX_QUEUE + 4:
        m._enqueue_splice(Vector3(i, 0, 0), Vector3.ONE)
    assert_lt(m._splice_queue.size(), m._MAX_QUEUE + 1, "queue stayed bounded")
    assert_eq(m._last_center, Vector3.INF, "overflow coalesces to one full re-mesh")


func test_edit_during_build_is_recorded_for_requeue():
    var m := _mgr()
    m._task_id = 999            # fake in-flight full build
    m._on_terrain_edit(_event(Vector3(8, 8, 8), Vector3.ONE * 6))
    assert_eq(m._edits_during_build.size(), 1, "edit during a build is recorded (re-queued on finish)")
    assert_eq(m._splice_queue.size(), 1, "and is also queued normally")
    m._task_id = -1             # reset so teardown doesn't touch a fake task


func test_dispatch_out_of_core_falls_back_to_full_remesh():
    var m := _mgr()
    m._cache_arrays = [1]       # non-empty base so _dispatch_splice proceeds past the cache guard
    m._cache_origin = Vector3i.ZERO
    m._last_center = Vector3.ZERO
    m._splice_queue = [[Vector3(9000, 9000, 9000), Vector3.ONE]]   # far outside the fine core
    m._dispatch_splice()
    assert_eq(m._splice_task_id, -1, "no worker dispatched for an out-of-core edit")
    assert_eq(m._last_center, Vector3.INF, "it falls back to a full re-mesh")
