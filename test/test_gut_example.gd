extends GutTest

class TestVoxelUtilsIsInSphere:
    extends GutTest

    var pos    := Vector3(4, 3, 0)
    var center := Vector3(0, 0, 0)

    func test_outside_radius():
        assert_false(VoxelUtils.is_in_sphere(pos, center, 4.0))

    func test_on_boundary():
        assert_true( VoxelUtils.is_in_sphere(pos, center, 5.0))

    func test_inside_radius():
        assert_true( VoxelUtils.is_in_sphere(pos, center, 6.0))

class TestVoxelUtilsForEachInBoundingBox:
    extends GutTest

    var visited : Array[Vector3i] = []

    var cb = func(pos: Vector3i):
        visited.push_back(pos)

    func test_for_each_visits_correct_count():
        VoxelUtils.for_each_in_bounding_box(Vector3.ZERO, Vector3.ONE * 3, cb)

        assert_eq(visited.size(), 27)

    func test_for_each_visits_correct_positions():
        assert_true( visited.has(Vector3i.ZERO     ))
        assert_true( visited.has(Vector3i.ONE      ))
        assert_true( visited.has(Vector3i.ONE  *  2))

        assert_false(visited.has(Vector3i.ONE  *  3))
        assert_false(visited.has(Vector3i.ONE  * -1))
