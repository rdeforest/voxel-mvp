class_name HelpOverlay
extends CanvasLayer

# A toggleable keybinding chart (the `?` key). Built in code as a centered panel
# over the HUD. The chart is one flat list — a single-element row is a section
# header, a two-element row is a [key, action] binding — rendered into a single
# 2-column grid so the columns line up across the whole chart.

const ROWS := [
    ["Move"],
    ["W A S D",            "Move"],
    ["Space",             "Jump"],
    ["X",                 "Toggle fly"],
    ["Mouse",             "Look"],
    ["Shift",             "Walk in place (suppress movement) — chord modifier"],

    ["Tools"],
    ["Tab",               "Cycle tool: None / Landscape / Construction / Assembly / CSG"],
    ["1 – 9",             "Pick an activity within the current tool"],
    ["Left-click",        "Use the current activity"],

    ["CSG  (CSG → Box / Cylinder / Sphere)"],
    ["1 / 2 / 3",         "Box / Cylinder / Sphere"],
    ["Wheel",             "Grow / shrink the active resize axis"],
    ["C",                 "Cycle resize axis (X / Y / Z, or radius / height)"],
    ["R / T / Y",         "Rotate around Y / X / Z (15° steps)"],
    ["M",                 "Cycle material"],
    ["B",                 "Toggle add / subtract"],
    ["Shift+W/A/E + wheel", "Nudge placement: depth / left-right / up-down"],

    ["Build  (Construction → Build)"],
    ["[  /  ]",           "Previous / next part"],
    ["M",                 "Cycle material"],
    ["R / T / Y",         "Rotate around Y / X / Z (15° steps)"],
    ["Shift+W/A/E + wheel", "Nudge placement: depth / left-right / up-down"],

    ["Probe  (None → Probe)"],
    ["Left-click",        "Log the targeted cell's physics to the console"],
    ["Shift+W/A/E + wheel", "Move the probe target off the surface"],

    ["View / Debug"],
    ["V",                 "Toggle PBD stress lines"],
    ["G",                 "Toggle voxel grid overlay"],
    ["F",                 "Toggle scene wireframe"],
    ["`",                 "Console (commands: settle, physics_active, perf, reset, …)"],
    ["?",                 "This help"],

    ["System"],
    ["F5  /  F9",         "Save / load"],
    ["Q",                 "Quit"],
    ["Esc",               "Release the mouse"],
]


func _init() -> void:
    layer = 128   # above the HUD

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)

    var panel := PanelContainer.new()
    center.add_child(panel)

    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 24)
    panel.add_child(margin)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 10)
    margin.add_child(vbox)

    var title := Label.new()
    title.text = "Keybindings"
    title.add_theme_font_size_override("font_size", 22)
    vbox.add_child(title)

    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 28)
    grid.add_theme_constant_override("v_separation", 4)
    vbox.add_child(grid)

    for row in ROWS:
        if row.size() == 1:
            grid.add_child(_header(row[0]))
            grid.add_child(Label.new())   # spacer in column 2
        else:
            grid.add_child(_key(row[0]))
            grid.add_child(_plain(row[1]))

    visible = false


func toggle() -> void:
    visible = not visible


func _header(text: String) -> Label:
    var l := Label.new()
    l.text = text.to_upper()
    l.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
    l.add_theme_font_size_override("font_size", 13)
    return l

func _key(text: String) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
    return l

func _plain(text: String) -> Label:
    var l := Label.new()
    l.text = text
    return l
