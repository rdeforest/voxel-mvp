extends ToolWindow

# Always-on probe read-out, now a draggable paper card (see ToolWindow). Every frame it builds a
# probe at the current target (via ActionFactories.probe_report, tool-independent) and shows the
# same lines the None-tool click writes to the console — so you can sweep the camera over a scene
# and read each cell's SDF / material / tracking live. The click still logs to the console
# (ProbeAction.execute); this is the passive companion.

var player: CharacterBody3D   # set by player._ready()

var _label: Label


func _ready() -> void:
    window_id    = "probe"
    window_title = "Probe"
    set_fraction(Vector2(0.012, 0.22))
    super._ready()
    _label = Label.new()
    _label.add_theme_font_override("font", ThemeDB.fallback_font)  # monospace-ish; aligns columns
    _label.add_theme_font_size_override("font_size", 13)
    _label.add_theme_color_override("font_color", INK)
    content.add_child(_label)


func _process(_delta: float) -> void:
    if player == null or player.action_factories == null:
        return
    var aim: Aim = player.current_target()
    if aim == null:
        _label.text = "probe: (no target)"
        return
    _label.text = "\n".join(player.action_factories.probe_report(aim.position, aim.normal))
