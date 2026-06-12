extends CanvasLayer

# Floating, draggable tuning panel for the watercolour-spike shader uniforms (F10 to toggle).
# Writes the terrain ShaderMaterial live — the SAME cached instance the console set/get and
# DCTerrainManager use, so changes are immediate. Opening frees the mouse + pauses the tree (tune
# on a frozen frame, see changes live); closing recaptures the mouse + unpauses so you can fly and
# check that the wash sticks in motion. Self-contained: loads the material by path.

const MAT_PATH := "res://assets/materials/terrain_surface.tres"

# [uniform, default, min, max, step] — defaults mirror the shader so a field reads right before
# the material has an override.
const FLOATS := [
    ["wc_enable",      0.0,  0.0,  1.0,  1.0],
    ["wc_dilute",      0.28, 0.0,  1.0,  0.01],
    ["wc_desat",       0.20, 0.0,  1.0,  0.01],
    ["wc_bands",       4.0,  1.0,  8.0,  0.5],
    ["wc_paper_scale", 6.0,  0.1,  16.0, 0.1],
    ["wc_granulate",   0.18, 0.0,  1.0,  0.01],
    ["wc_turb_scale",  0.5,  0.05, 4.0,  0.05],
    ["wc_turb",        0.14, 0.0,  1.0,  0.01],
    ["wc_edge",        0.45, 0.0,  1.0,  0.01],
    ["wc_edge_start",  0.45, 0.0,  1.0,  0.01],
    ["grain_amount",   0.18, 0.0,  1.0,  0.01],
    ["grain_scale",    4.0,  0.1,  12.0, 0.1],
]
const PAPER_DEFAULT := Color(0.96, 0.95, 0.91)

var _mat: ShaderMaterial
var _panel: PanelContainer
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS   # work (and toggle) while the tree is paused
    layer = 10
    _mat = load(MAT_PATH)
    _build_ui()
    visible = false


func _build_ui() -> void:
    _panel = PanelContainer.new()
    _panel.position = Vector2(24, 90)
    add_child(_panel)
    var vb := VBoxContainer.new()
    _panel.add_child(vb)

    var title := Label.new()
    title.text = "  Watercolour  (F10)  —  drag"
    title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
    title.mouse_filter = Control.MOUSE_FILTER_STOP
    title.gui_input.connect(_on_title_input)
    vb.add_child(title)
    vb.add_child(HSeparator.new())

    for f in FLOATS:
        var row := HBoxContainer.new()
        var lbl := Label.new()
        lbl.text = f[0]
        lbl.custom_minimum_size.x = 150
        var sb := SpinBox.new()
        sb.min_value = f[2]
        sb.max_value = f[3]
        sb.step = f[4]
        sb.custom_minimum_size.x = 110
        var cur: Variant = _mat.get_shader_parameter(f[0])
        sb.value = float(cur) if cur != null else float(f[1])
        sb.value_changed.connect(_on_float_changed.bind(f[0]))
        row.add_child(lbl)
        row.add_child(sb)
        vb.add_child(row)

    var crow := HBoxContainer.new()
    var clbl := Label.new()
    clbl.text = "wc_paper_color"
    clbl.custom_minimum_size.x = 150
    var cp := ColorPickerButton.new()
    cp.custom_minimum_size = Vector2(110, 0)
    var ccur: Variant = _mat.get_shader_parameter("wc_paper_color")
    cp.color = ccur if ccur != null else PAPER_DEFAULT
    cp.color_changed.connect(func(c: Color): _mat.set_shader_parameter("wc_paper_color", c))
    crow.add_child(clbl)
    crow.add_child(cp)
    vb.add_child(crow)


func _on_float_changed(value: float, uniform: String) -> void:
    _mat.set_shader_parameter(uniform, value)


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
