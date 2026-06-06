class_name PbdSolver
extends RefCounted

# Position-Based Dynamics (XPBD) solver for a PbdNetwork. Each step is substepped;
# within a substep, distance constraints are projected `iterations` times. Compliance
# decouples stiffness from iteration count, so the solver is stable at 60 Hz even for
# very stiff members (the reason for XPBD over an explicit mass-spring integrator).
# After the step, members past their tension/compression strain limit break. Pure
# computation over a PbdNetwork — no terrain/scene, headless-testable.

var gravity:    Vector3 = Vector3(0.0, -9.8, 0.0)
var substeps:   int     = 4
var iterations: int     = 8
var damping:    float   = 0.99   # velocity retained per substep


func step(net: PbdNetwork, dt: float) -> void:
    var h := dt / float(substeps)
    var inv_h2 := 1.0 / (h * h)
    for k in net.m_force.size():
        net.m_force[k] = 0.0
    for _s in substeps:
        _integrate(net, h)
        for k in net.m_lambda.size():
            net.m_lambda[k] = 0.0
        for _it in iterations:
            _project(net, h)
        _update_velocity(net, h)
        # The XPBD multiplier IS the constraint force: f = -lambda / h^2 (+tension).
        # Keep the peak-magnitude force this step for the breakage test.
        for k in net.m_a.size():
            if net.m_broken[k] != 0:
                continue
            var f := -net.m_lambda[k] * inv_h2
            if absf(f) > absf(net.m_force[k]):
                net.m_force[k] = f
    _break_overstressed(net)


func _integrate(net: PbdNetwork, h: float) -> void:
    for i in net.pos.size():
        if net.inv_mass[i] == 0.0:
            continue
        net.prev[i] = net.pos[i]
        net.vel[i] += gravity * h
        net.pos[i] += net.vel[i] * h


# One XPBD pass over the distance constraints. C = |b-a| - rest; correction splits by
# inverse mass so a pinned endpoint (inv_mass 0) absorbs all of it.
func _project(net: PbdNetwork, h: float) -> void:
    var inv_h2 := 1.0 / (h * h)
    for k in net.m_a.size():
        if net.m_broken[k] != 0:
            continue
        var a := net.m_a[k]
        var b := net.m_b[k]
        var wa := net.inv_mass[a]
        var wb := net.inv_mass[b]
        var w := wa + wb
        if w == 0.0:
            continue
        var d := net.pos[b] - net.pos[a]
        var dist := d.length()
        if dist == 0.0:
            continue
        var n := d / dist
        var c := dist - net.m_rest[k]
        var a_tilde := net.m_compliance[k] * inv_h2
        var dlambda := (-c - a_tilde * net.m_lambda[k]) / (w + a_tilde)
        net.m_lambda[k] += dlambda
        var corr := n * dlambda
        net.pos[a] -= corr * wa
        net.pos[b] += corr * wb


func _update_velocity(net: PbdNetwork, h: float) -> void:
    for i in net.pos.size():
        if net.inv_mass[i] == 0.0:
            continue
        net.vel[i] = (net.pos[i] - net.prev[i]) / h * damping


func _break_overstressed(net: PbdNetwork) -> void:
    for k in net.m_a.size():
        if net.m_broken[k] != 0:
            continue
        var f := net.m_force[k]
        if f > net.m_tension[k] or f < -net.m_compression[k]:
            net.m_broken[k] = 1
