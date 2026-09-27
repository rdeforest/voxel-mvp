extends GutTest

# The dcmaxcells surface: the effective limit mirrors Octree::cell_limit, 0 restores the default,
# and the help and status text derive from the RAM-budget capacity instead of restating a number.

var _capacity := DCOctreeMesher.get_cell_capacity()


func _preview() -> DcWorldPreview:
    return autofree(DcWorldPreview.new())


func test_default_limit_is_the_capacity():
    var wp := _preview()

    assert_eq(wp.max_cells, _capacity)
    assert_eq(wp.cell_limit(), _capacity)


func test_max_cells_lowers_the_limit():
    var wp := _preview()
    wp.set_max_cells(5_000_000)

    assert_eq(wp.cell_limit(), 5_000_000)


func test_max_cells_cannot_raise_the_limit():
    var wp := _preview()
    wp.set_max_cells(_capacity + 1)

    assert_eq(wp.cell_limit(), _capacity)


func test_zero_restores_the_default():
    var wp := _preview()
    wp.set_max_cells(5_000_000)
    wp.set_max_cells(0)

    assert_eq(wp.max_cells, _capacity)
    assert_eq(wp.cell_limit(), _capacity)


func test_cell_stats_before_any_build():
    var cells := _preview().cell_stats()

    assert_eq(cells.live, 0)
    assert_eq(cells.slots, 0)
    assert_eq(cells.capacity, _capacity)
    assert_eq(cells.limit, _capacity)
    assert_false(cells.at_limit, "no octree yet, so nothing to be full")


func test_report_notes_a_clamped_request():
    var cells := {"capacity": 100, "limit": 100, "live": 40, "slots": 60, "at_limit": false}

    assert_string_contains(ConsoleCommands.dcmaxcells_report(150, cells), "RAM budget caps it")
    assert_false(ConsoleCommands.dcmaxcells_report(100, cells).contains("caps it"))


func test_report_separates_live_cells_from_slots():
    var cells := {"capacity": 100_000_000, "limit": 8_000_000, "live": 4_000_000, "slots": 6_000_000,
            "at_limit": true}
    var text := ConsoleCommands.dcmaxcells_report(8_000_000, cells)

    assert_string_contains(text, "limit 8.0M cells")
    assert_string_contains(text, "4.0M live in 6.0M slots")
    assert_string_contains(text, "refinement holds")


func test_help_quotes_the_capacity():
    for entry in ConsoleCommands.new()._table():
        if entry[1] == "dcmaxcells":
            assert_string_contains(entry[2], "%.1fM cells" % (_capacity / 1.0e6))
            return

    fail_test("dcmaxcells is not in the command table")
