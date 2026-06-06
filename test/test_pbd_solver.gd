extends GutTest

# Phase 1: the XPBD solver core (PbdNetwork + PbdSolver), headless, no terrain.
# Proves: pinned anchors hold; a column stands; a chain hangs in tension (the
# "pulled from above" / suspension case); members break past their strain limit; a
# short cantilever truss holds while a long one fails (the headline Poly-Bridge
# behavior); and the solver never explodes at high stiffness.

const DT := 1.0 / 60.0
const STIFF := 1.0e-7        # near-rigid
const STRONG := 100.0        # effectively unbreakable strain limit


func _settle(solver: PbdSolver, net: PbdNetwork, steps: int) -> void:
    for _i in steps:
        solver.step(net, DT)

func _finite(net: PbdNetwork) -> bool:
    for i in net.node_count():
        if not net.pos[i].is_finite():
            return false
    return true

# A 2-row horizontal truss cantilever of `length` cells, pinned at the x=0 column,
# cross-braced per cell (face + both diagonals) so it's rigid until a member breaks.
func _cantilever(net: PbdNetwork, length: int, tension: float, compression: float) -> Array:
    var bottom: Array[int] = []
    var top: Array[int] = []
    for x in length + 1:
        var pinned := 1.0 if x > 0 else 0.0
        bottom.append(net.add_node(Vector3(x, 0, 0), pinned))
        top.append(net.add_node(Vector3(x, 1, 0), pinned))
    var add := func(a: int, b: int) -> void: net.add_member(a, b, STIFF, tension, compression)
    for x in length + 1:
        add.call(bottom[x], top[x])                       # vertical
        if x < length:
            add.call(bottom[x], bottom[x + 1])            # bottom chord
            add.call(top[x], top[x + 1])                  # top chord
            add.call(bottom[x], top[x + 1])               # diagonal
            add.call(top[x], bottom[x + 1])               # diagonal
    return [bottom, top]


func test_pinned_node_never_moves():
    var net := PbdNetwork.new()
    var a := net.add_node(Vector3(0, 5, 0), 0.0)
    _settle(PbdSolver.new(), net, 60)
    assert_eq(net.pos[a], Vector3(0, 5, 0))


func test_column_stands():
    var net := PbdNetwork.new()
    var nodes: Array[int] = []
    for y in 6:
        nodes.append(net.add_node(Vector3(0, y, 0), 0.0 if y == 0 else 1.0))
    for y in 5:
        net.add_member(nodes[y], nodes[y + 1], STIFF, STRONG, STRONG)
    _settle(PbdSolver.new(), net, 300)
    assert_eq(net.live_member_count(), 5, "nothing broke")
    assert_almost_eq(net.pos[nodes[5]].y, 5.0, 0.1, "top held its height")
    assert_true(_finite(net))


func test_hanging_chain_holds_in_tension():
    var net := PbdNetwork.new()
    var nodes: Array[int] = []
    for y in 6:
        nodes.append(net.add_node(Vector3(0, -y, 0), 0.0 if y == 0 else 1.0))
    for y in 5:
        net.add_member(nodes[y], nodes[y + 1], 1.0e-6, STRONG, STRONG)
    _settle(PbdSolver.new(), net, 300)
    assert_eq(net.live_member_count(), 5, "nothing broke")
    assert_lt(net.pos[nodes[5]].y, net.pos[nodes[0]].y, "hangs below the anchor")
    assert_gt(net.strain(2), 0.0, "members are in tension")
    assert_true(_finite(net))


func test_overstretched_member_breaks_and_falls():
    var net := PbdNetwork.new()
    var top := net.add_node(Vector3(0, 0, 0), 0.0)
    var hang := net.add_node(Vector3(0, -1, 0), 50.0)             # heavy
    net.add_member(top, hang, 1.0e-4, 0.02, STRONG)              # compliant, weak in tension
    var solver := PbdSolver.new()
    _settle(solver, net, 120)
    assert_eq(net.live_member_count(), 0, "weak member snapped under the heavy mass")
    var y0 := net.pos[hang].y
    _settle(solver, net, 60)
    assert_lt(net.pos[hang].y, y0, "released mass free-falls")


func test_short_cantilever_holds_long_breaks():
    # Force limit between a short cantilever's root force and a long one's (the long
    # one's bending moment is far larger), so the same material holds the short span
    # and fails the long one — the headline Poly-Bridge behavior.
    var limit := 250.0
    var short_net := PbdNetwork.new()
    _cantilever(short_net, 3, limit, limit)
    _settle(PbdSolver.new(), short_net, 400)
    assert_eq(short_net.live_member_count(), short_net.member_count(), "short cantilever holds")
    assert_true(_finite(short_net))

    var long_net := PbdNetwork.new()
    _cantilever(long_net, 16, limit, limit)
    _settle(PbdSolver.new(), long_net, 400)
    assert_lt(long_net.live_member_count(), long_net.member_count(), "long cantilever fails")


func test_no_explosion_at_high_stiffness():
    var net := PbdNetwork.new()
    var nodes: Array[int] = []
    for y in 10:
        nodes.append(net.add_node(Vector3(0, y, 0), 0.0 if y == 0 else 1.0))
    for y in 9:
        net.add_member(nodes[y], nodes[y + 1], 1.0e-9, STRONG, STRONG)   # extremely stiff
    _settle(PbdSolver.new(), net, 600)
    assert_true(_finite(net), "no NaN/Inf at extreme stiffness")
    var top_speed := net.vel[nodes[9]].length()
    assert_lt(top_speed, 5.0, "velocities stay bounded (no blow-up)")
