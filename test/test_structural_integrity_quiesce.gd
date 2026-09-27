extends GutTest

# force_quiescent (console `settle`) must say so when the support fixpoint won't drain,
# instead of stopping at its pass limit and leaving the caller to assume it settled.


class StuckSupport:
    extends TerrainSupport

    func process_dirty_queue() -> void:
        pass


func _integrity_with(support: TerrainSupport) -> StructuralIntegrity:
    var integrity: StructuralIntegrity = autofree(StructuralIntegrity.new())
    integrity.terrain_support = support
    return integrity


func test_drained_queue_reports_settled() -> void:
    var integrity := _integrity_with(TerrainSupport.new())

    assert_true(integrity.force_quiescent(), "an empty queue is settled")
    assert_push_error_count(0, "nothing to report when it settles")


func test_undrainable_queue_reports_failure() -> void:
    var support := StuckSupport.new()
    support.dirty_queue.append(Vector3i(1, 2, 3))
    var integrity := _integrity_with(support)

    assert_eq(integrity.force_quiescent(), false, "a queue still dirty at the pass limit is not settled")
    assert_push_error("did not settle", "the give-up is logged, not silent")
    assert_false(integrity.is_quiescent(), "the save gate still refuses")


# (Drafted by Claude, overnight 2026-09-27.) A freeze writes the store at once but announces a large
# region a few chunks per frame; the announcements are what register the frozen pile with support.
# A save between the freeze and its last announcement would keep the pile but lose its registration,
# so the gate waits for them as it waits for material in flight.
func test_the_save_gate_waits_for_freeze_announcements() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(manager.store)
    var integrity := _integrity_with(TerrainSupport.new())
    integrity.mpm = ms

    ms._queue_freeze_chunks(Vector3(0, 40, 0), 3 * MpmStructure.CHUNK, CellFlips.new())
    assert_eq(ms.active_count(), 0, "precondition: nothing in flight")
    assert_false(integrity.is_quiescent(), "not quiescent while the freeze is still being announced")

    while not ms._pending_chunks.is_empty():
        ms.tick(1.0 / 60.0)
    assert_true(integrity.is_quiescent(), "quiescent once every chunk is announced")
