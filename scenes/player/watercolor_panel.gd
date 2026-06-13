extends CanvasLayer

# Floating, draggable tuning panel for the watercolour-spike shader uniforms (F10 to toggle).
# Writes the terrain ShaderMaterial live — the SAME cached instance the console set/get and
# DCTerrainManager use, so changes are immediate. Opening frees the mouse + pauses the tree (tune
# on a frozen frame, see changes live); closing recaptures the mouse + unpauses so you can fly and
# check that the wash sticks in motion. Self-contained: loads the material by path.

const MAT_PATH := "res://assets/materials/terrain_surface.tres"
const POST_PATH := "res://assets/materials/watercolor_post.tres"

# [uniform, default, min, max, step, target, tooltip] — defaults mirror the shaders so a field reads
# right before the material has an override. target "t" = terrain wash material, "p" = ink/vignette post.
const FLOATS := [
    ["wc_enable",       0.0,  0.0,  1.0,  1.0,  "t", "Master toggle for the watercolour wash (0 off, 1 on)."],
    ["rock_mottle_scale",0.7, 0.05, 3.0,  0.05, "t", "Sarsen stone blotch size. Lower = bigger lichen patches / mottle (1/scale ≈ metres)."],
    ["rock_warmth",     0.40, 0.0,  1.0,  0.01, "t", "Sarsen warm buff/tan undertone strength (0 = cool grey)."],
    ["rock_lichen",     0.35, 0.0,  1.0,  0.01, "t", "Fraction of stone covered in lichen blotches."],
    ["rock_crevice",    0.35, 0.0,  1.0,  0.01, "t", "Sarsen crevice darkening (fake ambient occlusion in the pits)."],
    ["wc_dilute",       0.28, 0.0,  1.0,  0.01, "t", "Base dilution: lift the whole wash toward paper white (washiness)."],
    ["wc_desat",        0.20, 0.0,  1.0,  0.01, "t", "Desaturate toward washy grey (lower colour intensity)."],
    ["wc_bands",        4.0,  1.0,  8.0,  0.5,  "t", "Number of flat wash value-levels. Fewer = more posterised/graphic."],
    ["wc_paper_mode",   1.0,  0.0,  3.0,  1.0,  "t", "Paper tooth space: 0 none, 1 SCREEN noise (fixed sheet), 2 WORLD noise (sticks to surfaces / papercraft), 3 TEXTURE (real scanned paper, screen-space)."],
    ["wc_paper_scale",  6.0,  0.1,  16.0, 0.1,  "t", "Paper tooth size. Larger = coarser grain (px in screen mode, world units in world mode)."],
    ["wc_granulate",    0.18, 0.0,  1.0,  0.01, "t", "Paper granulation: pigment darkening in the paper tooth."],
    ["wc_turb_scale",   0.5,  0.05, 4.0,  0.05, "t", "Pigment-turbulence frequency (size of the world-space colour splotches)."],
    ["wc_turb",         0.14, 0.0,  1.0,  0.01, "t", "Pigment turbulence: world-space colour/density variation (sticks to surfaces, shows depth)."],
    ["wc_cangiante_amt",0.0,  0.0,  1.0,  0.01, "t", "Cangiante: highlights shift toward a brighter HUE (not just white). 0 = off."],
    ["wc_dilute_light", 0.0,  0.0,  1.0,  0.01, "t", "Extra dilution where the surface faces the light (more bare paper in highlights). 0 = off."],
    ["wc_edge",         0.45, 0.0,  1.0,  0.01, "t", "Edge darkening: pigment pooling at silhouettes (grazing angles)."],
    ["wc_edge_start",   0.45, 0.0,  1.0,  0.01, "t", "Grazing angle at which silhouette edge-darkening begins."],
    ["wc_sprig_amount", 0.5,  0.0,  1.0,  0.01, "t", "Grass sprig marks strength (0 = off)."],
    ["wc_sprig_freq",   2.5,  0.2,  10.0, 0.1,  "t", "Grass sprig mark size/frequency."],
    ["wc_sprig_patch",  0.4,  0.05, 2.0,  0.01, "t", "Grass sprig sparseness. Lower = sparser/clumpier, higher = everywhere."],
    ["wc_sprig_flat",   0.3,  0.0,  1.0,  0.01, "t", "Sprigs on flat grass vs only at slope-breaks. 0 = only at the base of things, 1 = everywhere."],
    ["ink_enable",      1.0,  0.0,  1.0,  1.0,  "p", "Master toggle for the ink line pass."],
    ["ink_depth_sens",  14.0, 0.0,  60.0, 0.5,  "p", "How strongly depth jumps (silhouettes) become ink. Raise if lines are missing."],
    ["ink_normal_sens", 1.4,  0.0,  6.0,  0.05, "p", "How strongly surface creases (normal changes) become ink lines."],
    ["ink_thresh",      0.40, 0.0,  2.0,  0.01, "p", "Edge cutoff. Raise to draw fewer lines (less dithering on distant detail)."],
    ["ink_gain",        4.0,  0.5,  12.0, 0.1,  "p", "Line hardness. Lower = softer/painterly, higher = crisp."],
    ["ink_tremor",      1.6,  0.0,  6.0,  0.1,  "p", "Hand-tremor wobble on the lines. Higher = shakier / more hand-drawn."],
    ["ink_width",       1.2,  0.5,  4.0,  0.1,  "p", "Line sample step / thickness."],
    ["vig_enable",      1.0,  0.0,  1.0,  1.0,  "p", "Master toggle for the vignette (fade to paper at the edges)."],
    ["vig_inner",       0.62, 0.0,  1.5,  0.01, "p", "Where the vignette fade begins (0 centre .. 1 edge)."],
    ["vig_outer",       1.05, 0.0,  1.5,  0.01, "p", "Where the vignette reaches full bare paper."],
    ["vig_round",       0.5,  0.0,  1.0,  0.01, "p", "Vignette corner shape: 0 hard rectangle .. 1 circle (rounds the corners)."],
    ["grain_amount",    0.18, 0.0,  1.0,  0.01, "t", "Non-watercolour material grain (the older wood-grain striation)."],
    ["grain_scale",     4.0,  0.1,  12.0, 0.1,  "t", "Material grain frequency."],
]
# [uniform, default-Color, target, tooltip]
const COLORS := [
    ["wc_paper_color", Color(0.96, 0.95, 0.91), "t", "The paper white the wash dilutes toward."],
    ["rock_lichen_green", Color(0.52, 0.56, 0.42), "t", "Sarsen lichen tint A (pale grey-green)."],
    ["rock_lichen_ochre", Color(0.62, 0.55, 0.36), "t", "Sarsen lichen tint B (ochre / rust)."],
    ["wc_cangiante",   Color(1.00, 0.96, 0.72), "t", "Cangiante highlight hue-shift target (warm/bright). Pair with wc_cangiante_amt."],
    ["wc_sprig_color", Color(0.16, 0.30, 0.12), "t", "Grass sprig mark colour."],
    ["ink_color",      Color(0.13, 0.11, 0.15), "p", "Ink line colour. A warm brown-black reads more like real ink than pure black."],
    ["vig_paper",      Color(0.97, 0.96, 0.93), "p", "The paper colour the vignette fades to at the edges."],
]

var _mat: ShaderMaterial
var _post: ShaderMaterial
var _panel: PanelContainer
var _scroll: ScrollContainer
var _fields: Array = []      # [widget, uniform, tag, is_color] — for re-reading after a loadstyle
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

    for f in FLOATS: _add_float_row(f, vb)
    for c in COLORS: _add_color_row(c, vb)


func _add_float_row(f: Array, vb: VBoxContainer) -> void:
    var sb := SpinBox.new()
    sb.min_value = f[2]
    sb.max_value = f[3]
    sb.step      = f[4]
    sb.custom_minimum_size.x = 110
    var cur: Variant = _target(f[5]).get_shader_parameter(f[0])
    sb.value = float(cur) if cur != null else float(f[1])
    sb.value_changed.connect(_on_float_changed.bind(f[0], f[5]))
    _fields.append([sb, f[0], f[5], false])
    _add_row(vb, f[0], f[5], f[6], sb)


func _add_color_row(c: Array, vb: VBoxContainer) -> void:
    var cp := ColorPickerButton.new()
    cp.custom_minimum_size = Vector2(110, 0)
    var cur: Variant = _target(c[2]).get_shader_parameter(c[0])
    cp.color = cur if cur != null else c[1]
    cp.color_changed.connect(_on_color_changed.bind(c[0], c[2]))
    _fields.append([cp, c[0], c[2], true])
    _add_row(vb, c[0], c[2], c[3], cp)


# A labelled row: "uniform [tag]" + its widget, both carrying the same hover tooltip.
func _add_row(vb: VBoxContainer, uniform: String, tag: String, tip: String, widget: Control) -> void:
    var lbl := Label.new()
    lbl.text = "%s [%s]" % [uniform, tag]
    lbl.custom_minimum_size.x = 170
    lbl.tooltip_text   = tip
    lbl.mouse_filter   = Control.MOUSE_FILTER_STOP   # so the label shows its tooltip on hover
    widget.tooltip_text = tip
    var row := HBoxContainer.new()
    row.add_child(lbl)
    row.add_child(widget)
    vb.add_child(row)


# Re-read every field from its material (so a console `loadstyle` shows up in the panel on open).
func _refresh() -> void:
    for fld in _fields:
        var cur: Variant = _target(fld[2]).get_shader_parameter(fld[1])
        if cur == null:
            continue
        if fld[3]:
            fld[0].color = cur                 # ColorPickerButton.color setter doesn't emit
        else:
            fld[0].set_value_no_signal(float(cur))


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
    if visible:
        _refresh()   # pick up any console loadstyle since it was last open
    get_tree().paused = visible
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED)
