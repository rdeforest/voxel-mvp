extends GutTest

class TestToolBasics:
    extends GutTest

    func test_tool_holds_name_and_activities():
        var em := EditMode.new().named("Probe")
        var t := Tool.new("None", [em] as Array[EditMode])
        assert_eq(t.name, "None")
        assert_eq(t.activities.size(), 1)
        assert_eq(t.activities[0].mode_name, "Probe")

    func test_tool_with_empty_activities():
        var t := Tool.new("Empty", [] as Array[EditMode])
        assert_eq(t.activities.size(), 0)


# Activity-memory pattern: the player carries an `_activity_indices`
# array (one per tool). This test exercises the index-bookkeeping
# without spinning up a full player.
class TestActivityMemoryPattern:
    extends GutTest

    var tools: Array[Tool]
    var activity_indices: Array[int]

    func before_each() -> void:
        var a := EditMode.new().named("A")
        var b := EditMode.new().named("B")
        var c := EditMode.new().named("C")
        tools = [
            Tool.new("None",         [a] as Array[EditMode]),
            Tool.new("Landscape",    [a, b, c] as Array[EditMode]),
            Tool.new("Construction", [a, b] as Array[EditMode]),
        ]
        activity_indices = [0, 0, 0]

    func _current_activity_name(tool_idx: int) -> String:
        return tools[tool_idx].activities[activity_indices[tool_idx]].mode_name

    func test_default_starts_at_activity_zero():
        assert_eq(_current_activity_name(0), "A")
        assert_eq(_current_activity_name(1), "A")

    func test_remembers_last_activity_per_tool():
        activity_indices[1] = 2   # Landscape → C
        assert_eq(_current_activity_name(1), "C")

        activity_indices[2] = 1   # Construction → B
        assert_eq(_current_activity_name(2), "B")

        # Switching among tools doesn't disturb each tool's memory.
        assert_eq(_current_activity_name(1), "C")
        assert_eq(_current_activity_name(2), "B")
        assert_eq(_current_activity_name(0), "A")
