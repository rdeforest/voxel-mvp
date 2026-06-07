class_name AwakeOverlay
extends Node3D

# Debug overlay: draws a box around every AWAKE RigidBody3D (falling debris, collapsed
# parts) so you can see at a glance what hasn't settled to sleep. No box = asleep.
# Drawn no-depth-test so awake bodies show through terrain. Toggle: `awake` console
# command. Off by default; skips work when headless.

const COLOR := Color(1.0, 0.25, 0.1)
const EDGES := [
    [0, 1], [1, 3], [3, 2], [2, 0],
    [4, 5], [5, 7], [7, 6], [6, 4],
    [0, 4], [1, 5], [2, 6], [3, 7],
]

var _world:    Node
var _mi:       MeshInstance3D
var _im:       ImmediateMesh
var _enabled := false
var _headless := false


func setup(world: Node) -> void:
    _world = world
    _headless = DisplayServer.get_name() == "headless"
    _im = ImmediateMesh.new()
    _mi = MeshInstance3D.new()
    _mi.mesh = _im
    var mat := StandardMaterial3D.new()
    mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.vertex_color_use_as_albedo = true
    mat.no_depth_test              = true   # see awake bodies through terrain
    _mi.material_override = mat
    _mi.visible = false
    add_child(_mi)


func is_enabled() -> bool:
    return _enabled

func set_enabled(on: bool) -> void:
    _enabled = on
    _mi.visible = on
    if not on:
        _im.clear_surfaces()


func _process(_dt: float) -> void:
    if _headless or not _enabled:
        return
    _im.clear_surfaces()
    var boxes: Array[AABB] = []
    for child in _world.get_children():
        var rb := child as RigidBody3D
        if rb != null and not rb.sleeping:
            boxes.append(_world_aabb(rb))
    if boxes.is_empty():
        return
    _im.surface_begin(Mesh.PRIMITIVE_LINES)
    _im.surface_set_color(COLOR)
    for aabb in boxes:
        for edge in EDGES:
            _im.surface_add_vertex(_corner(aabb, edge[0]))
            _im.surface_add_vertex(_corner(aabb, edge[1]))
    _im.surface_end()


# World-space AABB of a body, merged from its mesh children (falls back to a small
# box at the origin if it has none).
func _world_aabb(body: Node3D) -> AABB:
    var aabb := AABB()
    var has_any := false
    for child in body.get_children():
        var mi := child as MeshInstance3D
        if mi == null or mi.mesh == null:
            continue
        var world := mi.global_transform * mi.mesh.get_aabb()
        aabb = world if not has_any else aabb.merge(world)
        has_any = true
    if not has_any:
        return AABB(body.global_position - Vector3.ONE * 0.5, Vector3.ONE)
    return aabb

static func _corner(aabb: AABB, i: int) -> Vector3:
    return aabb.position + aabb.size * Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))
