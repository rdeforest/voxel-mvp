extends GutTest

# Phase 2: PbdNetworkBuilder — deriving the spring network from a tracked cell set.
# Headless: the "is this natural terrain?" predicate is a fake set, so no terrain.


func _pred(natural: Dictionary) -> Callable:
    return func(c: Vector3i) -> bool: return natural.has(c)


func test_base_cell_is_anchored_rest_are_free():
    # Column at x=z=0, y=1..5; natural terrain is the cell (0,0,0) directly below.
    var cells := {}
    for y in range(1, 6):
        cells[Vector3i(0, y, 0)] = null
    var r := PbdNetworkBuilder.build(cells, _pred({ Vector3i(0, 0, 0): true }))
    var net: PbdNetwork = r["network"]
    var node_of_cell: Dictionary = r["node_of_cell"]
    assert_eq(net.node_count(), 5)
    assert_eq(net.inv_mass[node_of_cell[Vector3i(0, 1, 0)]], 0.0, "base (touching terrain) is pinned")
    assert_gt(net.inv_mass[node_of_cell[Vector3i(0, 3, 0)]], 0.0, "interior cell is free")


func test_suspension_anchor_from_overhead_terrain():
    # A single tracked cell with natural terrain directly ABOVE it → pinned (hanging).
    var cells := { Vector3i(0, 0, 0): null }
    var r := PbdNetworkBuilder.build(cells, _pred({ Vector3i(0, 1, 0): true }))
    var net: PbdNetwork = r["network"]
    assert_eq(net.inv_mass[0], 0.0, "cell hung from overhead terrain is a pinned anchor")


func test_unanchored_cell_is_free():
    var cells := { Vector3i(5, 5, 5): null }
    var r := PbdNetworkBuilder.build(cells, _pred({}))
    var net: PbdNetwork = r["network"]
    assert_gt(net.inv_mass[0], 0.0, "isolated cell with no terrain neighbour is free")


func test_face_and_diagonal_members():
    # L-shape: (0,0,0)-(1,0,0) face, (1,0,0)-(1,1,0) face, (0,0,0)-(1,1,0) edge-diagonal.
    var cells := {
        Vector3i(0, 0, 0): null,
        Vector3i(1, 0, 0): null,
        Vector3i(1, 1, 0): null,
    }
    var r := PbdNetworkBuilder.build(cells, _pred({}))
    var net: PbdNetwork = r["network"]
    assert_eq(net.member_count(), 3, "two face members + one diagonal brace")


func test_node_cell_maps_round_trip():
    var cells := { Vector3i(2, 0, 0): null, Vector3i(2, 1, 0): null }
    var r := PbdNetworkBuilder.build(cells, _pred({}))
    var node_of_cell: Dictionary = r["node_of_cell"]
    var cell_of_node: Array = r["cell_of_node"]
    for cell in node_of_cell:
        assert_eq(cell_of_node[node_of_cell[cell]], cell)


func test_built_column_settles_under_solver():
    # End-to-end: build an anchored column, run the solver, it should stand.
    var cells := {}
    for y in range(1, 5):
        cells[Vector3i(0, y, 0)] = null
    var r := PbdNetworkBuilder.build(cells, _pred({ Vector3i(0, 0, 0): true }))
    var net: PbdNetwork = r["network"]
    var solver := PbdSolver.new()
    for _i in 200:
        solver.step(net, 1.0 / 60.0)
    assert_eq(net.live_member_count(), net.member_count(), "column holds")
    for i in net.node_count():
        assert_true(net.pos[i].is_finite())
