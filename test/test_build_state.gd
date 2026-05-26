extends GutTest

class TestBuildStatePlacementOffset:
    extends GutTest

    var bs: BuildState

    func before_each() -> void:
        bs = BuildState.new()

    func test_initial_offset_is_zero():
        assert_eq(bs.placement_offset, Vector3.ZERO)

    func test_adjust_offset_accumulates():
        bs.adjust_offset(Vector3(0.05, 0.0, 0.0))
        bs.adjust_offset(Vector3(0.0,  0.10, 0.0))
        bs.adjust_offset(Vector3(0.0,  0.0,  0.20))
        assert_eq(bs.placement_offset, Vector3(0.05, 0.10, 0.20))

    func test_adjust_offset_handles_negatives():
        bs.adjust_offset(Vector3(0.5, 0.5, 0.5))
        bs.adjust_offset(Vector3(-0.5, -0.5, -0.5))
        assert_eq(bs.placement_offset, Vector3.ZERO)

    func test_reset_offset_clears():
        bs.adjust_offset(Vector3(1, 2, 3))
        bs.reset_offset()
        assert_eq(bs.placement_offset, Vector3.ZERO)


class TestBuildStateRotationAndCycling:
    extends GutTest

    var bs: BuildState

    func before_each() -> void:
        bs = BuildState.new()

    func test_rotation_wraps_at_4():
        for i in 5:
            bs.rotate_y()
        assert_eq(bs.rotation.y, 1, "5 quarter turns around Y == 1 quarter turn")

    func test_three_axes_independent():
        bs.rotate_y()
        bs.rotate_y()
        bs.rotate_x()
        bs.rotate_z()
        assert_eq(bs.rotation, Vector3i(1, 2, 1))

    func test_part_cycle_wraps():
        var initial_name := bs.part_name()
        # Cycle forward through all parts back to start.
        for i in 4:   # 4 parts in catalog
            bs.next_part()
        assert_eq(bs.part_name(), initial_name)

    func test_prev_part_inverse_of_next():
        var initial_name := bs.part_name()
        bs.next_part()
        bs.prev_part()
        assert_eq(bs.part_name(), initial_name)

    func test_material_cycle_wraps():
        var initial := bs.current_material()
        for i in 5:   # 5 materials
            bs.cycle_material()
        assert_eq(bs.current_material(), initial)
