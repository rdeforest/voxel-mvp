class_name ToolWindow
extends PanelContainer

# A small draggable "paper card" for HUD read-outs (matches the line-and-wash look: a warm
# semi-opaque card with dark ink text, so the text reads over both the painting and the bright
# vignette paper at the edges). Stores its position as a FRACTION of the viewport, not pixels, so
# it lands proportionally after a resolution / fullscreen change, and re-applies that fraction
# whenever the viewport resizes. Persists via the "tool_window" group (WorldSnapshot reads/writes
# each window's id -> fraction on F5/F9). Drag the title bar — the mouse must be free (F10 panel or
# the console open). Set window_id / window_title before adding to the tree.

const PAPER  := Color(0.96, 0.94, 0.88, 0.85)
const INK    := Color(0.20, 0.15, 0.11)
const BORDER := Color(0.32, 0.26, 0.20, 0.55)

var window_id    := ""
var window_title := "Window"
var content: VBoxContainer        # callers add their labels here

var _frac        := Vector2(0.02, 0.02)
var _dragging    := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
    add_to_group("tool_window")
    _build()
    _apply_fraction()
    get_viewport().size_changed.connect(_apply_fraction)


func _build() -> void:
    var style := StyleBoxFlat.new()
    style.bg_color     = PAPER
    style.border_color = BORDER
    style.set_corner_radius_all(6)
    style.set_border_width_all(1)
    style.set_content_margin_all(8)
    add_theme_stylebox_override("panel", style)

    var vb := VBoxContainer.new()
    add_child(vb)

    var title := Label.new()
    title.text         = window_title
    title.mouse_filter = Control.MOUSE_FILTER_STOP
    title.add_theme_color_override("font_color", INK)
    title.gui_input.connect(_on_title_input)
    vb.add_child(title)
    vb.add_child(HSeparator.new())

    content = VBoxContainer.new()
    vb.add_child(content)


func set_fraction(f: Vector2) -> void:
    _frac = f
    if is_inside_tree():
        _apply_fraction()

func get_fraction() -> Vector2:
    return _frac


# fraction -> pixels, clamped so the card can't be dragged (or restored) fully off-screen.
func _apply_fraction() -> void:
    var vp := get_viewport().get_visible_rect().size
    var pos: Vector2 = _frac * vp
    pos.x = clamp(pos.x, 0.0, max(0.0, vp.x - size.x))
    pos.y = clamp(pos.y, 0.0, max(0.0, vp.y - 24.0))   # keep at least the title bar on screen
    position = pos

func _store_fraction() -> void:
    var vp := get_viewport().get_visible_rect().size
    if vp.x > 0.0 and vp.y > 0.0:
        _frac = position / vp


func _on_title_input(event: InputEvent) -> void:
    if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
        return   # can't grab the title while the mouse is captured (playing)
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _dragging    = event.pressed
        _drag_offset = global_position - event.global_position
    elif event is InputEventMouseMotion and _dragging:
        global_position = event.global_position + _drag_offset
        _store_fraction()
