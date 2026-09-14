class_name MpmDemo
extends Node3D

# A watchable demo of the PB-MPM continuum solver (MpmSim, C++): spawn a block of elastic
# material in front of the player, simulate it live, and render each particle as a small cube
# via MultiMesh. The collider is the real terrain (the EditStore SDF), so the block falls and
# rests ON the world — the grid-resolved contact a mass-spring model couldn't do (doc 12). Console:
# `mpmdemo [size]`. Standalone — touches nothing else; re-run to respawn. Stepping runs at the
# physics rate, drawing once per rendered frame.

const PARTICLE_SIZE := 0.45
const RHO := 400.0
const GRID_DIM := 40   # the grid re-centres on the block each step, so it never reaches the walls

var _sim: MpmSim
var _mm: MultiMesh


func _ready() -> void:
    _mm = MultiMesh.new()
    _mm.transform_format = MultiMesh.TRANSFORM_3D
    var box := BoxMesh.new()
    box.size = Vector3.ONE * PARTICLE_SIZE
    _mm.mesh = box
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = _mm
    mmi.material_override = _make_material()
    add_child(mmi)


# Spawn a `side`-cell elastic block centred at `center`, colliding against the terrain SDF.
func setup(center: Vector3, side: int, edit_store: EditStore) -> void:
    _sim = MpmSim.new()
    var origin := (center - Vector3.ONE * (GRID_DIM * 0.5)).floor()
    _sim.configure(origin, GRID_DIM, 1.0, Vector3(0, -9.8, 0), -1.0e9)
    _sim.set_material(0)            # elastic
    _sim.set_iterations(4)
    _sim.set_elastic(1.0, 0.5)     # rotation target, under-relaxed — the stable recipe
    _sim.set_recenter(true)        # the grid follows the block — no domain-wall bouncing
    _sim.set_sdf_collider(edit_store)

    var p_vol := 0.125             # 8 particles per 1 m³ cell
    var p_mass := RHO * p_vol
    var half := side * 0.5
    for cz in side:
        for cy in side:
            for cx in side:
                var corner := center + Vector3(cx - half, cy - half, cz - half)
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            _sim.add_particle(corner + Vector3(ox, oy, oz), p_mass, p_vol)
    _mm.instance_count = _sim.particle_count()


func _physics_process(delta: float) -> void:
    if _sim != null:
        _sim.step(delta)


func _process(_dt: float) -> void:
    if _sim == null:
        return
    for i in _sim.particle_count():
        _mm.set_instance_transform(i, Transform3D(Basis(), _sim.get_position(i)))


static func _make_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.55, 0.38, 0.20)
    mat.roughness = 0.9
    return mat
