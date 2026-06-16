extends Node3D

# Per-frame voxel-aware preview for the current EditMode. Renders the cells
# the action would change at the player's current target, with two passes:
#
#   Visible pass: depth-tested, full alpha — what you can actually see.
#   Obscured pass: no-depth-test, faint alpha — what's hidden behind terrain.
#
# Each cell contributes a wireframe outline (lines). Cells with "solid" or
# "part" intent also contribute a translucent filled box.
#
# Colors keyed to intent. Refused actions lerp toward grey.

const COLOR_AIR    := Color(1.0, 0.35, 0.25)   # red-ish — cell empties out
const COLOR_SOLID  := Color(0.30, 0.55, 1.0)   # blue-ish — cell fills in
const COLOR_PART   := Color(1.0, 0.90, 0.25)   # yellow  — part placement
const COLOR_GREY   := Color(0.6, 0.6, 0.6)

const VISIBLE_ALPHA_LINE  := 1.0
const VISIBLE_ALPHA_FILL  := 0.12
const VISIBLE_ALPHA_AIR   := 0.06    # very faint hint-fill for cells that empty out
const OBSCURED_ALPHA_LINE := 0.25
const OBSCURED_ALPHA_FILL := 0.04
const OBSCURED_ALPHA_AIR  := 0.0
const REFUSED_GREY_BLEND  := 0.7

# Inset the wireframe slightly inside each cell so lines don't sit exactly on
# the Transvoxel surface (z-fight) and adjacent cells don't double-draw the
# shared edge.
const INSET := 0.05

# 6 faces × 2 triangles each, indexed by cube corners.
const FACE_TRIS := [
    # -Y
    [0, 1, 3], [0, 3, 2],
    # +Y
    [4, 5, 7], [4, 7, 6],
    # -X
    [0, 2, 6], [0, 6, 4],
    # +X
    [1, 3, 7], [1, 7, 5],
    # -Z
    [0, 1, 5], [0, 5, 4],
    # +Z
    [2, 3, 7], [2, 7, 6],
]

var player: CharacterBody3D   # set by player._ready()

var _visible_mi:  MeshInstance3D
var _obscured_mi: MeshInstance3D
var _visible_im:  ImmediateMesh
var _obscured_im: ImmediateMesh


func _ready() -> void:
    _visible_mi  = _make_pass(false)
    _obscured_mi = _make_pass(true)
    _visible_im  = _visible_mi.mesh
    _obscured_im = _obscured_mi.mesh
    add_child(_visible_mi)
    add_child(_obscured_mi)

func _process(_delta: float) -> void:
    _visible_im.clear_surfaces()
    _obscured_im.clear_surfaces()
    if player == null or not player.is_focused():
        return
    var mode: EditMode = player.current_activity()
    if mode == null:
        return
    var aim: Aim = player.current_target()
    if aim == null:
        return
    var action: Action = mode.make_action.call(aim.position, aim.normal)
    if action == null:
        return
    var p := action.preview()
    if not aim.hit and not mode.acts_on_air:
        p.refused = true   # air target this mode won't act on (CSG) — show it inert
    if p.is_empty():
        return
    _draw_pass(_visible_im,  p, VISIBLE_ALPHA_LINE,  VISIBLE_ALPHA_FILL,  VISIBLE_ALPHA_AIR)
    _draw_pass(_obscured_im, p, OBSCURED_ALPHA_LINE, OBSCURED_ALPHA_FILL, OBSCURED_ALPHA_AIR)


# --- Geometry build ---

func _draw_pass(im: ImmediateMesh, p: ActionPreview, line_a: float, fill_a: float, air_a: float) -> void:
    var c_air   := _tinted(COLOR_AIR,   p.refused)
    var c_solid := _tinted(COLOR_SOLID, p.refused)
    var c_part  := _tinted(COLOR_PART,  p.refused)

    im.surface_begin(Mesh.PRIMITIVE_LINES)
    for cell in p.air:    _emit_lines(im, cell, c_air,   line_a)
    for cell in p.solid:  _emit_lines(im, cell, c_solid, line_a)
    for cell in p.part:   _emit_lines(im, cell, c_part,  line_a)
    im.surface_end()

    var draw_fills := not p.solid.is_empty() or not p.part.is_empty() or (air_a > 0.0 and not p.air.is_empty())
    if not draw_fills:
        return
    im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
    for cell in p.solid:  _emit_tris(im, cell, c_solid, fill_a)
    for cell in p.part:   _emit_tris(im, cell, c_part,  fill_a)
    if air_a > 0.0:
        for cell in p.air: _emit_tris(im, cell, c_air, air_a)
    im.surface_end()

func _emit_lines(im: ImmediateMesh, cell: Vector3i, color: Color, alpha: float) -> void:
    var base := Vector3(cell)
    var c := color
    c.a = alpha
    im.surface_set_color(c)
    # Corners inset (CubeGeometry.corner_inset) so wireframes don't z-fight with the
    # terrain surface or double-draw shared edges with neighbours.
    for edge in CubeGeometry.EDGES:
        im.surface_add_vertex(base + CubeGeometry.corner_inset(edge[0], INSET))
        im.surface_add_vertex(base + CubeGeometry.corner_inset(edge[1], INSET))

func _emit_tris(im: ImmediateMesh, cell: Vector3i, color: Color, alpha: float) -> void:
    var base := Vector3(cell)
    var c := color
    c.a = alpha
    im.surface_set_color(c)
    for tri in FACE_TRIS:
        im.surface_add_vertex(base + CubeGeometry.corner_inset(tri[0], INSET))
        im.surface_add_vertex(base + CubeGeometry.corner_inset(tri[1], INSET))
        im.surface_add_vertex(base + CubeGeometry.corner_inset(tri[2], INSET))

static func _tinted(c: Color, refused: bool) -> Color:
    return c.lerp(COLOR_GREY, REFUSED_GREY_BLEND) if refused else c


# --- Setup ---

func _make_pass(obscured: bool) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh              = ImmediateMesh.new()
    mi.material_override = OverlayMaterial.make(obscured)
    return mi
