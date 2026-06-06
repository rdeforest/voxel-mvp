extends GutTest

# PbdNetworkBuilder — deriving the PbdSim network from a tracked cell set. Headless:
# the "is this natural terrain?" predicate is a fake set, so no terrain needed.


func _pred(natural: Dictionary) -> Callable:
    return func(c: Vector3i) -> bool: return natural.has(c)


func test_base_cell_is_anchored_rest_are_free():
    var cells := {}
    for y in range(1, 6):
        cells[Vector3i(0, y, 0)] = null
    var r := PbdNetworkBuilder.build(cells, _pred({ Vector3i(0, 0, 0): true }))
    var sim: PbdSim = r["sim"]
    var node_of_cell: Dictionary = r["node_of_cell"]
    assert_eq(sim.node_count(), 5)
    assert_true(sim.is_pinned(node_of_cell[Vector3i(0, 1, 0)]), "base (touching terrain) is pinned")
    assert_false(sim.is_pinned(node_of_cell[Vector3i(0, 3, 0)]), "interior cell is free")


func test_suspension_anchor_from_overhead_terrain():
    var cells := { Vector3i(0, 0, 0): null }
    var r := PbdNetworkBuilder.build(cells, _pred({ Vector3i(0, 1, 0): true }))
    var sim: PbdSim = r["sim"]
    assert_true(sim.is_pinned(0), "cell hung from overhead terrain is a pinned anchor")


func test_unanchored_cell_is_free():
    var r := PbdNetworkBuilder.build({ Vector3i(5, 5, 5): null }, _pred({}))
    var sim: PbdSim = r["sim"]
    assert_false(sim.is_pinned(0), "isolated cell with no terrain neighbour is free")


func test_face_and_diagonal_members():
    var cells := {
        Vector3i(0, 0, 0): null,
        Vector3i(1, 0, 0): null,
        Vector3i(1, 1, 0): null,
    }
    var sim: PbdSim = PbdNetworkBuilder.build(cells, _pred({}))["sim"]
    assert_eq(sim.member_count(), 3, "two face members + one diagonal brace")


func test_node_cell_maps_round_trip():
    var r := PbdNetworkBuilder.build({ Vector3i(2, 0, 0): null, Vector3i(2, 1, 0): null }, _pred({}))
    var node_of_cell: Dictionary = r["node_of_cell"]
    var cell_of_node: Array = r["cell_of_node"]
    for cell in node_of_cell:
        assert_eq(cell_of_node[node_of_cell[cell]], cell)


func test_anchor_count_reported():
    # The build's anchor count drives the load-time "terrain not streamed yet" guard.
    var anchored := PbdNetworkBuilder.build({Vector3i(0, 1, 0): null}, _pred({Vector3i(0, 0, 0): true}))
    assert_eq(anchored["anchor_count"], 1, "one cell touching terrain → one anchor")
    var floating := PbdNetworkBuilder.build({Vector3i(5, 5, 5): null}, _pred({}))
    assert_eq(floating["anchor_count"], 0, "no terrain contact → no anchors")


func test_member_strength_from_material():
    var cells := {Vector3i(0, 0, 0): Materials.WOOD, Vector3i(1, 0, 0): Materials.WOOD}
    var sim: PbdSim = PbdNetworkBuilder.build(cells, _pred({}))["sim"]
    assert_almost_eq(sim.member_tension(0),     Materials.WOOD.tension,     0.5, "member tension from material")
    assert_almost_eq(sim.member_compression(0), Materials.WOOD.compression, 0.5, "member compression from material")


func test_member_uses_weakest_of_two_materials():
    var cells := {Vector3i(0, 0, 0): Materials.STONE, Vector3i(1, 0, 0): Materials.DIRT}
    var sim: PbdSim = PbdNetworkBuilder.build(cells, _pred({}))["sim"]
    assert_almost_eq(sim.member_tension(0), minf(Materials.STONE.tension, Materials.DIRT.tension), 0.5,
        "a member is as strong as its weaker endpoint (dirt here)")


# Same geometry, different material → different fate. Wood has high specific tensile
# strength (light + decent tension) so it cantilevers; dirt is weak and crumbles.
func _beam(material: Materials, length: int) -> PbdSim:
    var cells := {}
    for x in range(0, length + 1):
        cells[Vector3i(x, 0, 0)] = material
        cells[Vector3i(x, 1, 0)] = material
    return PbdNetworkBuilder.build(cells, _pred({Vector3i(-1, 0, 0): true, Vector3i(-1, 1, 0): true}))["sim"]

func test_material_strength_changes_collapse():
    var wood := _beam(Materials.WOOD, 3)
    var dirt := _beam(Materials.DIRT, 3)
    for _i in 600:
        wood.step(1.0 / 60.0)
        dirt.step(1.0 / 60.0)
    assert_eq(wood.live_member_count(), wood.member_count(), "wood cantilever holds")
    assert_lt(dirt.live_member_count(), dirt.member_count(), "dirt cantilever crumbles")


func test_built_column_settles_under_solver():
    var cells := {}
    for y in range(1, 5):
        cells[Vector3i(0, y, 0)] = null
    var sim: PbdSim = PbdNetworkBuilder.build(cells, _pred({ Vector3i(0, 0, 0): true }))["sim"]
    for _i in 200:
        sim.step(1.0 / 60.0)
    assert_eq(sim.live_member_count(), sim.member_count(), "column holds")
    for i in sim.node_count():
        assert_true(sim.get_position(i).is_finite())
