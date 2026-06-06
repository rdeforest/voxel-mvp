class_name PbdDemo
extends Node3D

# A standalone, watchable demo of the C++ PBD solver (PbdSim): build a cantilever /
# bridge / tower of cross-braced cells, simulate it live, and draw its members as
# stress-coloured lines (green→red). Overstressed members redden and snap; freed
# parts drop. Anchors are virtual. Console: `pbddemo`. Stepping runs at the fixed
# physics rate; drawing once per rendered frame.

var _sim: PbdSim
var _mesh: ArrayMesh


func _ready() -> void:
    _mesh = ArrayMesh.new()
    var mi := MeshInstance3D.new()
    mi.mesh = _mesh
    mi.material_override = PbdRenderer.make_material()
    add_child(mi)


func set_sim(sim: PbdSim) -> void:
    _sim = sim


func _physics_process(delta: float) -> void:
    if _sim != null:
        _sim.step(delta)


func _process(_dt: float) -> void:
    if _sim != null:
        PbdRenderer.draw(_sim, _mesh)


# --- structure builders (anchors are virtual "natural terrain" cells) ---

static func cantilever(base: Vector3i, length: int) -> PbdSim:
    var cells := {}
    for x in length + 1:
        cells[base + Vector3i(x, 0, 0)] = null
        cells[base + Vector3i(x, 1, 0)] = null
    var wall := { base + Vector3i(-1, 0, 0): true, base + Vector3i(-1, 1, 0): true }
    return _built(cells, wall)

static func bridge(base: Vector3i, span: int) -> PbdSim:
    var cells := {}
    for x in span + 1:
        cells[base + Vector3i(x, 0, 0)] = null
        cells[base + Vector3i(x, 1, 0)] = null
    var ends := {
        base + Vector3i(-1, 0, 0): true, base + Vector3i(-1, 1, 0): true,
        base + Vector3i(span + 1, 0, 0): true, base + Vector3i(span + 1, 1, 0): true,
    }
    return _built(cells, ends)

static func tower(base: Vector3i, height: int) -> PbdSim:
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

static func _built(cells: Dictionary, natural: Dictionary) -> PbdSim:
    var pred := func(c: Vector3i) -> bool: return natural.has(c)
    return PbdNetworkBuilder.build(cells, pred)["sim"]
