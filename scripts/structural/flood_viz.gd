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

var _store: EditStore
var _budget := 200
var _flood: GroundFlood
var _prev_visited := 0   # visited count after last step — new entries are the tail of the dict
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
    _budget       = budget
    _flood        = GroundFlood.new()
    _flood.start([cell], _store, MAX_VISITED)
    _prev_visited = 0
    _reached      = 0
    _mm.visible_instance_count = 0
    _running      = true


func _is_visible(cell: Vector3i) -> bool:
    for n in GroundFlood.NEIGHBORS:
        if not TerrainProbe.is_solid(_store, cell + n):
            return true
    return false


func _process(_dt: float) -> void:
    if not _running:
        return
    _flood.step(_budget)
    # GDScript Dictionaries preserve insertion order: entries after index _prev_visited are new.
    var keys := _flood.visited.keys()
    for idx in range(_prev_visited, keys.size()):
        var cell: Vector3i = keys[idx]
        if _reached < MAX_VISIBLE and _is_visible(cell):
            _mm.set_instance_transform(_reached, Transform3D(Basis(), Vector3(cell) + VoxelConstants.VOXEL_CENTER_OFFSET))
            _reached += 1
    _prev_visited = keys.size()
    _mm.visible_instance_count = _reached
    if _flood.state != GroundFlood.RUNNING:
        _running = false
        var stopped := "CAP HIT (never settled)" if _flood.visited.size() >= MAX_VISITED else "settled"
        print("floodviz: %s — reached %d cells, %d coloured" % [stopped, _flood.visited.size(), _reached])


static func _make_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(0.1, 1.0, 0.3) # bright green
    mat.no_depth_test = true                # see the flood through terrain
    return mat
