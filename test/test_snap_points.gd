extends GutTest

# SnapPoints resolves points through a prototype with copy-on-write, and stores
# own (forked) points in node-local space. An orphan Node3D's global_transform
# equals its local transform, so these tests exercise the world<->local math
# and the fork semantics without a scene tree.

const PROTO_EMPTY: Array = []


class TestSnapPointsRoundTrip:
    extends GutTest

    var node: Node3D

    func before_each() -> void:
        node = add_child_autofree(Node3D.new())

    func test_starts_unforked():
        assert_false(SnapPoints.has_own(node))
        assert_eq(SnapPoints.effective_local(node, []).size(), 0)

    func test_add_then_world_points_round_trips_under_translation():
        node.transform = Transform3D(Basis.IDENTITY, Vector3(10, 0, -5))
        SnapPoints.add(node, Vector3(11, 2, -5), [])
        var world := SnapPoints.world_points(node, [])
        assert_eq(world.size(), 1)
        assert_almost_eq(world[0], Vector3(11, 2, -5), Vector3.ONE * 0.0001)

    func test_own_is_relative_to_transform():
        node.transform = Transform3D(Basis.IDENTITY, Vector3(10, 0, -5))
        SnapPoints.add(node, Vector3(11, 2, -5), [])
        assert_almost_eq(SnapPoints.own_local(node)[0], Vector3(1, 2, 0), Vector3.ONE * 0.0001)

    func test_round_trips_under_rotation():
        node.transform = Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)), Vector3(3, 1, 7))
        SnapPoints.add(node, Vector3(4, 1, 9), [])
        assert_almost_eq(SnapPoints.world_points(node, [])[0], Vector3(4, 1, 9), Vector3.ONE * 0.0001)


class TestSnapPointsPrototypeInheritance:
    extends GutTest

    var node:  Node3D
    var proto: Array

    func before_each() -> void:
        node  = add_child_autofree(Node3D.new())
        proto = [Vector3(0, 0, 0), Vector3(2, 0, 0)]

    func test_unforked_instance_inherits_prototype():
        assert_false(SnapPoints.has_own(node))
        assert_eq(SnapPoints.effective_local(node, proto).size(), 2)

    func test_unforked_instance_tracks_prototype_changes():
        proto.append(Vector3(4, 0, 0))
        assert_eq(SnapPoints.effective_local(node, proto).size(), 3)

    func test_adding_forks_and_includes_inherited_points():
        SnapPoints.add(node, Vector3(9, 0, 0), proto)
        assert_true(SnapPoints.has_own(node))
        assert_eq(SnapPoints.own_local(node).size(), 3)   # 2 inherited + 1 new

    func test_forked_instance_ignores_later_prototype_changes():
        SnapPoints.add(node, Vector3(9, 0, 0), proto)
        proto.append(Vector3(100, 0, 0))
        assert_eq(SnapPoints.effective_local(node, proto).size(), 3)   # still 2+1


class TestSnapPointsRemoval:
    extends GutTest

    var node:  Node3D
    var proto: Array

    func before_each() -> void:
        node  = add_child_autofree(Node3D.new())
        proto = [Vector3(0, 0, 0), Vector3(5, 0, 0)]

    func test_remove_nearest_within_radius_forks():
        assert_true(SnapPoints.remove_nearest(node, Vector3(0.2, 0, 0), 0.4, proto))
        assert_true(SnapPoints.has_own(node))
        assert_eq(SnapPoints.own_local(node).size(), 1)
        assert_almost_eq(SnapPoints.world_points(node, proto)[0], Vector3(5, 0, 0), Vector3.ONE * 0.0001)

    func test_remove_nearest_outside_radius_refuses_and_does_not_fork():
        assert_false(SnapPoints.remove_nearest(node, Vector3(2, 0, 0), 0.4, proto))
        assert_false(SnapPoints.has_own(node))

    func test_nearest_world_returns_null_when_out_of_range():
        assert_null(SnapPoints.nearest_world(node, Vector3(2, 0, 0), 0.4, proto))

    func test_nearest_world_returns_closest():
        assert_almost_eq(SnapPoints.nearest_world(node, Vector3(4.8, 0, 0), 0.4, proto), Vector3(5, 0, 0), Vector3.ONE * 0.0001)


class TestPartPrototypeDefaults:
    extends GutTest

    func test_board_ships_with_two_end_snap_points():
        var board: Part = preload("res://assets/parts/board/board.tres")
        assert_eq(board.snap_points.size(), 2)
        assert_almost_eq(board.snap_points[0], Vector3(1, 0.05, 0), Vector3.ONE * 0.0001)


class TestSnapDelta:
    extends GutTest

    func test_no_world_points_means_no_snap():
        var ghost := PackedVector3Array([Vector3(0, 0, 0)])
        assert_eq(SnapPoints.snap_delta(ghost, PackedVector3Array(), 0.75), Vector3.ZERO)

    func test_out_of_range_means_no_snap():
        var ghost := PackedVector3Array([Vector3(0, 0, 0)])
        var world := PackedVector3Array([Vector3(2, 0, 0)])
        assert_eq(SnapPoints.snap_delta(ghost, world, 0.75), Vector3.ZERO)

    func test_pulls_ghost_onto_world_point():
        var ghost := PackedVector3Array([Vector3(0.5, 0, 0)])
        var world := PackedVector3Array([Vector3(1, 0, 0)])
        assert_almost_eq(SnapPoints.snap_delta(ghost, world, 0.75), Vector3(0.5, 0, 0), Vector3.ONE * 0.0001)

    func test_picks_closest_pair_among_many():
        var ghost := PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0)])
        var world := PackedVector3Array([Vector3(0.6, 0, 0), Vector3(5.1, 0, 0)])
        # nearest pair is (5,0,0)->(5.1,0,0), delta 0.1, beating (0->0.6, delta 0.6)
        assert_almost_eq(SnapPoints.snap_delta(ghost, world, 0.75), Vector3(0.1, 0, 0), Vector3.ONE * 0.0001)
