extends CanvasLayer

# Floating, draggable tuning panel for the watercolour-spike shader uniforms (F10 to toggle).
# Writes the terrain ShaderMaterial live — the SAME cached instance the console set/get and
# DCTerrainManager use, so changes are immediate. Opening frees the mouse + pauses the tree (tune
# on a frozen frame, see changes live); closing recaptures the mouse + unpauses so you can fly and
# check that the wash sticks in motion. Self-contained: loads the material by path.

const MAT_PATH := "res://assets/materials/terrain_surface.tres"
const POST_PATH := "res://assets/materials/watercolor_post.tres"

# [uniform, default, min, max, step, target] — defaults mirror the shaders so a field reads right
# before the material has an override. target "t" = terrain wash material, "p" = ink/vignette post.
const FLOATS := [
    ["wc_enable",       0.0,  0.0,  1.0,  1.0,  "t"],
    ["wc_dilute",       0.28, 0.0,  1.0,  0.01, "t"],
    ["wc_desat",        0.20, 0.0,  1.0,  0.01, "t"],
    ["wc_bands",        4.0,  1.0,  8.0,  0.5,  "t"],
    ["wc_paper_scale",  6.0,  0.1,  16.0, 0.1,  "t"],
    ["wc_granulate",    0.18, 0.0,  1.0,  0.01, "t"],
    ["wc_turb_scale",   0.5,  0.05, 4.0,  0.05, "t"],
    ["wc_turb",         0.14, 0.0,  1.0,  0.01, "t"],
    ["wc_edge",         0.45, 0.0,  1.0,  0.01, "t"],
    ["wc_edge_start",   0.45, 0.0,  1.0,  0.01, "t"],
    ["ink_enable",      1.0,  0.0,  1.0,  1.0,  "p"],
    ["ink_depth_sens",  14.0, 0.0,  60.0, 0.5,  "p"],
    ["ink_normal_sens", 1.4,  0.0,  6.0,  0.05, "p"],
    ["ink_thresh",      0.40, 0.0,  2.0,  0.01, "p"],
    ["ink_gain",        4.0,  0.5,  12.0, 0.1,  "p"],
    ["ink_tremor",      1.6,  0.0,  6.0,  0.1,  "p"],
    ["ink_width",       1.2,  0.5,  4.0,  0.1,  "p"],
    ["vig_enable",      1.0,  0.0,  1.0,  1.0,  "p"],
    ["vig_inner",       0.62, 0.0,  1.5,  0.01, "p"],
    ["vig_outer",       1.05, 0.0,  1.5,  0.01, "p"],
    ["grain_amount",    0.18, 0.0,  1.0,  0.01, "t"],
    ["grain_scale",     4.0,  0.1,  12.0, 0.1,  "t"],
]
# [uniform, default-Color, target]
const COLORS := [
    ["wc_paper_color", Color(0.96, 0.95, 0.91), "t"],
    ["ink_color",      Color(0.13, 0.11, 0.15), "p"],
    ["vig_paper",      Color(0.97, 0.96, 0.93), "p"],
]

var _mat: ShaderMaterial
var _post: ShaderMaterial
var _panel: PanelContainer
var _scroll: ScrollContainer
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS   # work (and toggle) while the tree is paused
    layer = 10
    _mat = load(MAT_PATH)
    _post = load(POST_PATH)
    _build_ui()
    visible = false


func _target(tag: String) -> ShaderMaterial:
    return _post if tag == "p" else _mat


func _build_ui() -> void:
    _panel = PanelContainer.new()
    _panel.position = Vector2(24, 90)
    add_child(_panel)
    var outer := VBoxContainer.new()
    _panel.add_child(outer)

    var title := Label.new()
    title.text = "  Watercolour  (F10)  —  drag      [t]=wash  [p]=ink/vignette"
    title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
    title.mouse_filter = Control.MOUSE_FILTER_STOP
    title.gui_input.connect(_on_title_input)
    outer.add_child(title)
    outer.add_child(HSeparator.new())

    _scroll = ScrollContainer.new()
    _scroll.custom_minimum_size = Vector2(300, 460)
    outer.add_child(_scroll)
    var vb := VBoxContainer.new()
    vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _scroll.add_child(vb)

    for f in FLOATS:
        var mat := _target(f[5])
        var row := HBoxContainer.new()
        var lbl := Label.new()
        lbl.text = "%s [%s]" % [f[0], f[5]]
        lbl.custom_minimum_size.x = 170
        var sb := SpinBox.new()
        sb.min_value = f[2]
        sb.max_value = f[3]
        sb.step = f[4]
        sb.custom_minimum_size.x = 110
        var cur: Variant = mat.get_shader_parameter(f[0])
        sb.value = float(cur) if cur != null else float(f[1])
        sb.value_changed.connect(_on_float_changed.bind(f[0], f[5]))
        row.add_child(lbl)
        row.add_child(sb)
        vb.add_child(row)

    for c in COLORS:
        var mat := _target(c[2])
        var row := HBoxContainer.new()
        var lbl := Label.new()
        lbl.text = "%s [%s]" % [c[0], c[2]]
        lbl.custom_minimum_size.x = 170
        var cp := ColorPickerButton.new()
        cp.custom_minimum_size = Vector2(110, 0)
        var cur: Variant = mat.get_shader_parameter(c[0])
        cp.color = cur if cur != null else c[1]
        cp.color_changed.connect(_on_color_changed.bind(c[0], c[2]))
        row.add_child(lbl)
        row.add_child(cp)
        vb.add_child(row)


func _on_float_changed(value: float, uniform: String, tag: String) -> void:
    _target(tag).set_shader_parameter(uniform, value)

func _on_color_changed(color: Color, uniform: String, tag: String) -> void:
    _target(tag).set_shader_parameter(uniform, color)


func _on_title_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _dragging = event.pressed
        _drag_offset = _panel.global_position - event.global_position
    elif event is InputEventMouseMotion and _dragging:
        _panel.global_position = event.global_position + _drag_offset


func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
        _toggle()
        get_viewport().set_input_as_handled()


func _toggle() -> void:
    visible = not visible
    get_tree().paused = visible
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED)
