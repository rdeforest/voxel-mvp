extends GutTest

class TestActionPreviewBasics:
    extends GutTest

    func test_default_is_empty():
        var p := ActionPreview.new()
        assert_true(p.is_empty())
        assert_false(p.refused)

    func test_air_alone_is_not_empty():
        var p := ActionPreview.new()
        p.air.append(Vector3i(0, 0, 0))
        assert_false(p.is_empty())

    func test_solid_alone_is_not_empty():
        var p := ActionPreview.new()
        p.solid.append(Vector3i(0, 0, 0))
        assert_false(p.is_empty())

    func test_part_alone_is_not_empty():
        var p := ActionPreview.new()
        p.part.append(Vector3i(0, 0, 0))
        assert_false(p.is_empty())

    func test_mixed_intents_compose():
        var p := ActionPreview.new()
        p.air.append(  Vector3i(1, 0, 0))
        p.solid.append(Vector3i(0, 1, 0))
        p.part.append( Vector3i(0, 0, 1))
        assert_eq(p.air.size(),   1)
        assert_eq(p.solid.size(), 1)
        assert_eq(p.part.size(),  1)
        assert_false(p.is_empty())

    func test_refused_independent_of_emptiness():
        var p := ActionPreview.new()
        p.refused = true
        assert_true(p.is_empty(), "refused empty preview is still empty")
        p.solid.append(Vector3i.ZERO)
        assert_true(p.refused, "refused stays true when cells are added")
        assert_false(p.is_empty())
