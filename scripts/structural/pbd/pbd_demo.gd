class_name PbdDemo
extends Node3D

# A standalone, watchable demo of the PBD structural solver: build a cantilever /
# bridge / tower of cross-braced cells, simulate it live, and draw its members as
# lines coloured by axial-force ratio (green→red, Poly-Bridge style). Overstressed
# members redden and snap; freed parts drop. This exercises the real PbdNetworkBuilder
# + PbdSolver decoupled from the live world (anchors are virtual). Console: `pbddemo`.

var _net: PbdNetwork
var _solver := PbdSolver.new()
var _im: ImmediateMesh


func _ready() -> void:
    _im = ImmediateMesh.new()
    var mi := MeshInstance3D.new()
    mi.mesh = _im
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.vertex_color_use_as_albedo = true
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mi.material_override = mat
    add_child(mi)


func set_network(net: PbdNetwork) -> void:
    _net = net


func _physics_process(delta: float) -> void:
    if _net == null:
        return
    _solver.step(_net, delta)
    _redraw()


func _redraw() -> void:
    _im.clear_surfaces()
    if _net.member_count() == 0:
        return
    _im.surface_begin(Mesh.PRIMITIVE_LINES)
    for k in _net.member_count():
        if _net.m_broken[k] != 0:
            continue
        var col := _stress_color(k)
        _im.surface_set_color(col)
        _im.surface_add_vertex(_net.pos[_net.m_a[k]])
        _im.surface_set_color(col)
        _im.surface_add_vertex(_net.pos[_net.m_b[k]])
    _im.surface_end()


func _stress_color(k: int) -> Color:
    var f := _net.m_force[k]
    var limit: float = _net.m_tension[k] if f >= 0.0 else _net.m_compression[k]
    var r := clampf(absf(f) / maxf(limit, 0.001), 0.0, 1.0)
    return Color(r, 1.0 - r, 0.0)   # green (slack) → yellow → red (at limit)


# --- structure builders (anchors are virtual "natural terrain" cells) ---

static func cantilever(base: Vector3i, length: int) -> PbdNetwork:
    var cells := {}
    for x in length + 1:
        cells[base + Vector3i(x, 0, 0)] = null
        cells[base + Vector3i(x, 1, 0)] = null
    var wall := { base + Vector3i(-1, 0, 0): true, base + Vector3i(-1, 1, 0): true }
    return _built(cells, wall)

static func bridge(base: Vector3i, span: int) -> PbdNetwork:
    var cells := {}
    for x in span + 1:
        cells[base + Vector3i(x, 0, 0)] = null
        cells[base + Vector3i(x, 1, 0)] = null
    var ends := {
        base + Vector3i(-1, 0, 0): true, base + Vector3i(-1, 1, 0): true,
        base + Vector3i(span + 1, 0, 0): true, base + Vector3i(span + 1, 1, 0): true,
    }
    return _built(cells, ends)

static func tower(base: Vector3i, height: int) -> PbdNetwork:
    var cells := {}
    for y in height + 1:
        for fx in 2:
            for fz in 2:
                cells[base + Vector3i(fx, y, fz)] = null
    var ground := {}
    for fx in 2:
        for fz in 2:
            ground[base + Vector3i(fx, -1, fz)] = true
    return _built(cells, ground)

static func _built(cells: Dictionary, natural: Dictionary) -> PbdNetwork:
    var pred := func(c: Vector3i) -> bool: return natural.has(c)
    return PbdNetworkBuilder.build(cells, pred)["network"]
