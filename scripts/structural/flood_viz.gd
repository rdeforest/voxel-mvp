class_name FloodViz
extends Node3D

# Debug scout for the MPM detachment trigger: flood-fill through connected solid terrain from a
# seed cell, BIASED DOWNWARD (so it dives toward where bedrock will be), colouring the reached
# VISIBLE (surface) cells bright. NON-BLOCKING — it spreads `budget` cells per frame so you can
# watch how far and how fast it reaches, and judge where a "connected to ground" stop belongs.
# Console: `floodviz [budget]`. No stop condition yet (that's the point — see what it reaches);
# a generous cap halts a runaway so you can tell "it never stopped" from "it settled".

const MAX_VISIBLE := 60000     # MultiMesh capacity for coloured (visible) cells
const MAX_VISITED := 400000    # generous reach cap — distinguishes "settled" from "floods forever"
const CELL_SIZE := 0.92
const NEIGHBORS := [
    Vector3i(0, -1, 0), # down first — the bias
    Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
    Vector3i(0, 0, 1), Vector3i(0, 0, -1),
    Vector3i(0, 1, 0),
]

var _store: EditStore
var _budget := 200
var _frontier: Array[Vector3i] = []
var _visited := {}
var _mm: MultiMesh
var _reached := 0
var _running := false


func setup(store: EditStore) -> void:
    _store = store
    _mm = MultiMesh.new()
    _mm.transform_format = MultiMesh.TRANSFORM_3D
    var box := BoxMesh.new()
    box.size = Vector3.ONE * CELL_SIZE
    _mm.mesh = box
    _mm.instance_count = MAX_VISIBLE
    _mm.visible_instance_count = 0
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = _mm
    mmi.material_override = _make_material()
    add_child(mmi)


# Seed a fresh flood from `cell`, processing `budget` cells per frame.
func start(cell: Vector3i, budget: int) -> void:
    _budget = budget
    _frontier = [cell]
    _visited = { cell: true }
    _reached = 0
    _mm.visible_instance_count = 0
    _running = true


func _is_solid(cell: Vector3i) -> bool:
    return _store.sample(Vector3(cell) + Vector3(0.5, 0.5, 0.5)) < VoxelConstants.SDF_SOLID_THRESHOLD

func _is_visible(cell: Vector3i) -> bool:
    for n in NEIGHBORS:
        if not _is_solid(cell + n):
            return true
    return false


func _process(_dt: float) -> void:
    if not _running:
        return
    var done := 0
    while not _frontier.is_empty() and done < _budget and _visited.size() < MAX_VISITED:
        var cell: Vector3i = _frontier.pop_front()
        done += 1
        if _reached < MAX_VISIBLE and _is_visible(cell):
            _mm.set_instance_transform(_reached, Transform3D(Basis(), Vector3(cell) + Vector3(0.5, 0.5, 0.5)))
            _reached += 1
        for n in NEIGHBORS:
            var nb: Vector3i = cell + n
            if _visited.has(nb) or not _is_solid(nb):
                continue
            _visited[nb] = true
            if n.y < 0:
                _frontier.push_front(nb) # dive down — process bedrock-ward cells first
            else:
                _frontier.push_back(nb)
    _mm.visible_instance_count = _reached
    if _frontier.is_empty() or _visited.size() >= MAX_VISITED:
        _running = false
        var stopped := "CAP HIT (never settled)" if _visited.size() >= MAX_VISITED else "settled"
        print("floodviz: %s — reached %d cells, %d coloured" % [stopped, _visited.size(), _reached])


static func _make_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(0.1, 1.0, 0.3) # bright green
    mat.no_depth_test = true                # see the flood through terrain
    return mat
