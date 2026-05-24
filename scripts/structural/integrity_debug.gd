class_name IntegrityDebug
extends RefCounted

# Diagnostic overlay for tracked-voxel support state. Two passes:
#   Visible pass — full wireframe outline of the cell, depth-tested.
#   Obscured pass — corner-bracket markers, no depth test. Off by default;
#     player toggles via show_obscured.
#
# Spatial filter: cells with support > ALWAYS_SHOW_MAX (i.e. better than
# orange) only render within FILTER_RADIUS of the player's raycast hit.
# Lower-support (orange / red / failed) cells always render so failures
# are never hidden.

const FILTER_RADIUS    := 6.0
const ALWAYS_SHOW_MAX  := 0.30
const INSET            := 0.05
const CORNER_STUB_LEN  := 0.18

const STRAIN_ALPHA_LO  := 0.20
const STRAIN_ALPHA_HI  := 0.95
const STEADY_ALPHA     := 0.85
const OBSCURED_FACTOR  := 0.35

const EDGES := [
    [0, 1], [1, 3], [3, 2], [2, 0],
    [4, 5], [5, 7], [7, 6], [6, 4],
    [0, 4], [1, 5], [2, 6], [3, 7],
]

var enabled:           bool = true
var show_obscured:     bool = false
var raycast:           RayCast3D     # set by player._ready()

var _terrain_support:  TerrainSupport
var _container:        Node
var _visible_mi:       MeshInstance3D
var _obscured_mi:      MeshInstance3D
var _visible_im:       ImmediateMesh
var _obscured_im:      ImmediateMesh


func _init(terrain_support: TerrainSupport, container: Node) -> void:
    _terrain_support = terrain_support
    _container       = container
    _visible_mi  = _make_pass(false)
    _obscured_mi = _make_pass(true)
    _visible_im  = _visible_mi.mesh
    _obscured_im = _obscured_mi.mesh
    _container.add_child.call_deferred(_visible_mi)
    _container.add_child.call_deferred(_obscured_mi)


func set_enabled(value: bool) -> void:
    enabled = value
    _visible_mi.visible  = enabled
    _obscured_mi.visible = enabled and show_obscured
    if not enabled:
        _visible_im.clear_surfaces()
        _obscured_im.clear_surfaces()

func toggle_obscured() -> void:
    show_obscured = not show_obscured
    _obscured_mi.visible = enabled and show_obscured

func update(pulse: float, straining: Dictionary) -> void:
    _visible_im.clear_surfaces()
    _obscured_im.clear_surfaces()
    if not enabled:
        return

    var pointer     := Vector3.ZERO
    var has_pointer := false
    if raycast != null and raycast.is_colliding():
        pointer     = raycast.get_collision_point()
        has_pointer = true

    var pulse_alpha := lerpf(STRAIN_ALPHA_LO, STRAIN_ALPHA_HI, pulse)
    var to_draw: Array = []   # [[pos, color, alpha], ...]

    for pos in _terrain_support.voxel_data:
        var support: float = _terrain_support.voxel_data[pos].support
        if support > ALWAYS_SHOW_MAX:
            if not has_pointer:
                continue
            if Vector3(pos).distance_squared_to(pointer) > FILTER_RADIUS * FILTER_RADIUS:
                continue
        var color := StructuralIntegrity.get_support_color(support)
        var alpha := pulse_alpha if straining.has(pos) else STEADY_ALPHA
        to_draw.append([pos, color, alpha])

    if to_draw.is_empty():
        return

    _visible_im.surface_begin(Mesh.PRIMITIVE_LINES)
    for entry in to_draw:
        _emit_outline(_visible_im, entry[0], entry[1], entry[2])
    _visible_im.surface_end()

    if show_obscured:
        _obscured_im.surface_begin(Mesh.PRIMITIVE_LINES)
        for entry in to_draw:
            _emit_corners(_obscured_im, entry[0], entry[1], entry[2] * OBSCURED_FACTOR)
        _obscured_im.surface_end()


# --- Geometry helpers ---

func _emit_outline(im: ImmediateMesh, cell: Vector3i, color: Color, alpha: float) -> void:
    var c := color
    c.a = alpha
    im.surface_set_color(c)
    var base := Vector3(cell)
    for edge in EDGES:
        im.surface_add_vertex(base + _corner(edge[0]))
        im.surface_add_vertex(base + _corner(edge[1]))

func _emit_corners(im: ImmediateMesh, cell: Vector3i, color: Color, alpha: float) -> void:
    var c := color
    c.a = alpha
    im.surface_set_color(c)
    var base := Vector3(cell)
    for i in 8:
        var corner_pos := base + _corner(i)
        var inward := Vector3(
            CORNER_STUB_LEN if (i & 1) == 0           else -CORNER_STUB_LEN,
            CORNER_STUB_LEN if ((i >> 1) & 1) == 0    else -CORNER_STUB_LEN,
            CORNER_STUB_LEN if ((i >> 2) & 1) == 0    else -CORNER_STUB_LEN,
        )
        im.surface_add_vertex(corner_pos)
        im.surface_add_vertex(corner_pos + Vector3(inward.x, 0, 0))
        im.surface_add_vertex(corner_pos)
        im.surface_add_vertex(corner_pos + Vector3(0, inward.y, 0))
        im.surface_add_vertex(corner_pos)
        im.surface_add_vertex(corner_pos + Vector3(0, 0, inward.z))

static func _corner(i: int) -> Vector3:
    var x := INSET if (i & 1) == 0          else 1.0 - INSET
    var y := INSET if ((i >> 1) & 1) == 0   else 1.0 - INSET
    var z := INSET if ((i >> 2) & 1) == 0   else 1.0 - INSET
    return Vector3(x, y, z)


# --- Setup ---

func _make_pass(obscured: bool) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh              = ImmediateMesh.new()
    mi.material_override = _make_material(obscured)
    mi.visible           = not obscured  # obscured-pass starts hidden until toggled
    return mi

static func _make_material(obscured: bool) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.vertex_color_use_as_albedo = true
    mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
    mat.no_depth_test              = obscured
    return mat
