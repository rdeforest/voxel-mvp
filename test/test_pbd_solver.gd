extends GutTest

# The C++ XPBD solver core (PbdSim), headless, no terrain. Proves: pinned anchors
# hold; a column stands; a chain hangs in tension (suspension); members break past
# their force limit; a short cantilever truss holds while a long one fails (the
# headline Poly-Bridge behaviour); and the solver never explodes at high stiffness.
# PbdSim defaults (gravity -9.8, 4 substeps, 8 iterations, 0.99 damping) match the
# original GDScript solver.

const DT := 1.0 / 60.0
const STIFF := 1.0e-7        # near-rigid
const STRONG := 100.0        # effectively unbreakable force limit


func _settle(sim: PbdSim, steps: int) -> void:
    for _i in steps:
        sim.step(DT)

func _finite(sim: PbdSim) -> bool:
    for i in sim.node_count():
        if not sim.get_position(i).is_finite():
            return false
    return true

# A 2-row horizontal truss cantilever of `length` cells, pinned at the x=0 column,
# cross-braced per cell (face + both diagonals) so it's rigid until a member breaks.
# Returns [bottom_nodes, top_nodes].
func _cantilever(sim: PbdSim, length: int, tension: float, compression: float, compliance := STIFF) -> Array:
    var bottom: Array[int] = []
    var top: Array[int] = []
    for x in length + 1:
        var pinned := 1.0 if x > 0 else 0.0
        bottom.append(sim.add_node(Vector3(x, 0, 0), pinned))
        top.append(sim.add_node(Vector3(x, 1, 0), pinned))
    var add := func(a: int, b: int) -> void: sim.add_member(a, b, compliance, tension, compression)
    for x in length + 1:
        add.call(bottom[x], top[x])
        if x < length:
            add.call(bottom[x], bottom[x + 1])
            add.call(top[x], top[x + 1])
            add.call(bottom[x], top[x + 1])
            add.call(top[x], bottom[x + 1])
    return [bottom, top]


func test_pinned_node_never_moves():
    var sim := PbdSim.new()
    var a := sim.add_node(Vector3(0, 5, 0), 0.0)
    _settle(sim, 60)
    assert_eq(sim.get_position(a), Vector3(0, 5, 0))


func test_column_stands():
    var sim := PbdSim.new()
    var nodes: Array[int] = []
    for y in 6:
        nodes.append(sim.add_node(Vector3(0, y, 0), 0.0 if y == 0 else 1.0))
    for y in 5:
        sim.add_member(nodes[y], nodes[y + 1], STIFF, STRONG, STRONG)
    _settle(sim, 300)
    assert_eq(sim.live_member_count(), 5, "nothing broke")
    assert_almost_eq(sim.get_position(nodes[5]).y, 5.0, 0.1, "top held its height")
    assert_true(_finite(sim))


func test_hanging_chain_holds_in_tension():
    var sim := PbdSim.new()
    var nodes: Array[int] = []
    for y in 6:
        nodes.append(sim.add_node(Vector3(0, -y, 0), 0.0 if y == 0 else 1.0))
    for y in 5:
        sim.add_member(nodes[y], nodes[y + 1], 1.0e-6, STRONG, STRONG)
    _settle(sim, 300)
    assert_eq(sim.live_member_count(), 5, "nothing broke")
    assert_lt(sim.get_position(nodes[5]).y, sim.get_position(nodes[0]).y, "hangs below the anchor")
    assert_gt(sim.member_force(2), 0.0, "members are in tension")
    assert_true(_finite(sim))


func test_overstressed_member_breaks_and_falls():
    var sim := PbdSim.new()
    var top := sim.add_node(Vector3(0, 0, 0), 0.0)
    var hang := sim.add_node(Vector3(0, -1, 0), 50.0)
    sim.add_member(top, hang, 1.0e-4, 0.02, STRONG)   # weak in tension
    _settle(sim, 120)
    assert_eq(sim.live_member_count(), 0, "weak member snapped under the heavy mass")
    var y0 := sim.get_position(hang).y
    _settle(sim, 60)
    assert_lt(sim.get_position(hang).y, y0, "released mass free-falls")


func test_short_cantilever_holds_long_breaks():
    var limit := 250.0
    var short_sim := PbdSim.new()
    _cantilever(short_sim, 3, limit, limit)
    _settle(short_sim, 400)
    assert_eq(short_sim.live_member_count(), short_sim.member_count(), "short cantilever holds")
    assert_true(_finite(short_sim))

    var long_sim := PbdSim.new()
    _cantilever(long_sim, 16, limit, limit)
    _settle(long_sim, 400)
    assert_lt(long_sim.live_member_count(), long_sim.member_count(), "long cantilever fails")


func test_no_explosion_at_high_stiffness():
    # At extreme stiffness the solver must stay finite + bounded (not diverge to
    # huge values / NaN). Unbreakable members + a braced, anchored structure so the
    # test isolates numerical stability, not breakage or buckling.
    const UNBREAKABLE := 1.0e9
    var sim := PbdSim.new()
    var rows := _cantilever(sim, 3, UNBREAKABLE, UNBREAKABLE, 1.0e-9)
    var tip: int = rows[1][3]
    var rest := sim.get_position(tip)
    _settle(sim, 600)
    assert_true(_finite(sim), "no NaN/Inf at extreme stiffness")
    assert_eq(sim.live_member_count(), sim.member_count(), "unbreakable members never break")
    assert_lt(sim.get_position(tip).distance_to(rest), 50.0, "bounded — no divergence to huge values")
