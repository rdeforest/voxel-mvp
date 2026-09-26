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
