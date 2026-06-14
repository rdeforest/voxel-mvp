extends Node3D

# Fading wireframe boxes showing what an edit or movement INVALIDATED — what the terrain system
# decided to re-mesh. BLUE = the voxel region an edit changed. GREEN = the triangle region it then
# re-meshed (the splice sub-box, or the fine region on a movement rebuild). Each box fades over
# LIFETIME, so per action you can watch whether the work it picked matches what you'd expect — a
# small edit should light a small green box; a green box far bigger than the blue one means the
# invalidation over-reached (the splice box ballooned). Toggle: `dcinval` in the console.

const LIFETIME := 5.0
const THICKNESS := 0.04                 # ImmediateMesh lines are 1px; draw each a few times offset
const BLUE  := Color(0.25, 0.55, 1.0)   # voxels an edit changed
const GREEN := Color(0.25, 1.0,  0.45)  # triangles re-meshed

var _boxes: Array = []   # [{min: Vector3, max: Vector3, color: Color, t: float}]
var _tris:  Array = []   # [{verts: PackedVector3Array (multiple of 3, world), t: float}]
var _im: ImmediateMesh
var _enabled := false
var _clock := 0.0


func _ready() -> void:
    _im = ImmediateMesh.new()
    var mi := MeshInstance3D.new()
    mi.mesh                 = _im
    mi.material_override     = _make_material()
    mi.cast_shadow           = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mi.custom_aabb           = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
    add_child(mi)


static func _make_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.vertex_color_use_as_albedo = true
    mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
    mat.no_depth_test              = true   # see the boxes through terrain
    mat.render_priority            = VoxelConstants.OVERLAY_RENDER_PRIORITY
    return mat


func toggle() -> bool:
    _enabled = not _enabled
    if not _enabled:
        _boxes.clear()
        _tris.clear()
        _im.clear_surfaces()
    return _enabled


# kind 0 = voxels (blue), 1 = triangles (green). World-space AABB. No-op when disabled.
func highlight(box_min: Vector3, box_max: Vector3, kind: int) -> void:
    if not _enabled:
        return
    _boxes.append({"min": box_min, "max": box_max, "color": BLUE if kind == 0 else GREEN, "t": _clock})


# The ACTUAL invalidated mesh triangles (world-space verts, groups of 3), drawn as green
# wireframes — shows the LOD/cell structure the alignment grabbed, not just its bounding box.
func highlight_triangles(world_verts: PackedVector3Array) -> void:
    if not _enabled or world_verts.size() < 3:
        return
    _tris.append({"verts": world_verts, "t": _clock})


func _process(dt: float) -> void:
    _clock += dt
    _im.clear_surfaces()
    if not _enabled or (_boxes.is_empty() and _tris.is_empty()):
        return
    var live_b: Array = []
    var live_t: Array = []
    _im.surface_begin(Mesh.PRIMITIVE_LINES)
    for b in _boxes:
        var age: float = _clock - b.t
        if age >= LIFETIME:
            continue
        live_b.append(b)
        var c: Color = b.color
        c.a = 1.0 - age / LIFETIME
        _emit_box(b.min, b.max, c)
    for tg in _tris:
        var age: float = _clock - tg.t
        if age >= LIFETIME:
            continue
        live_t.append(tg)
        var c := GREEN
        c.a = 1.0 - age / LIFETIME
        _emit_tris(tg.verts, c)
    _im.surface_end()
    _boxes = live_b
    _tris = live_t


func _emit_box(mn: Vector3, mx: Vector3, c: Color) -> void:
    var corner := [
        Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z),
        Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
        Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z),
        Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z),
    ]
    for e in [[0,1],[1,2],[2,3],[3,0], [4,5],[5,6],[6,7],[7,4], [0,4],[1,5],[2,6],[3,7]]:
        _line(corner[e[0]], corner[e[1]], c)


# Triangle soup (verts in groups of 3) as wireframe edges.
func _emit_tris(verts: PackedVector3Array, c: Color) -> void:
    var i := 0
    while i + 2 < verts.size():
        for e in [[0,1],[1,2],[2,0]]:
            _line(verts[i + e[0]], verts[i + e[1]], c)
        i += 3


# A segment, drawn as a few parallel copies offset along each axis so it reads as a thick line
# (ImmediateMesh has no line width). Cheap — three extra draws per edge.
func _line(a: Vector3, b: Vector3, c: Color) -> void:
    for offset in [Vector3.ZERO, Vector3(THICKNESS, 0, 0), Vector3(0, THICKNESS, 0), Vector3(0, 0, THICKNESS)]:
        _im.surface_set_color(c)
        _im.surface_add_vertex(a + offset)
        _im.surface_set_color(c)
        _im.surface_add_vertex(b + offset)
