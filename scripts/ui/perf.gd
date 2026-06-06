extends CanvasLayer

# Performance HUD (autoload `Perf`), bottom-right, console-toggled (`perf`). Shows
# FPS + frame time, plus per-subsystem time-per-frame: a system wraps its work and
# calls Perf.report("Name", ms) each frame. Entries not reported for a while drop
# off (e.g. when a subsystem is toggled off). Never captures input; runs while paused.

const STALE_FRAMES := 30
const SMOOTH := 0.15           # EMA factor for readability

var _times: Dictionary = {}    # label -> {ms: float, frame: int}
var _label: Label
var _shown := false


func _ready() -> void:
    layer = 127
    process_mode = Node.PROCESS_MODE_ALWAYS
    _label = Label.new()
    _label.anchor_left = 1.0
    _label.anchor_top = 1.0
    _label.anchor_right = 1.0
    _label.anchor_bottom = 1.0
    _label.offset_left = -380.0
    _label.offset_top = -240.0
    _label.offset_right = -12.0
    _label.offset_bottom = -10.0
    _label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    _label.grow_vertical = Control.GROW_DIRECTION_BEGIN
    _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    _label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
    _label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
    _label.add_theme_constant_override("outline_size", 5)
    _label.add_theme_font_size_override("font_size", 16)
    _label.visible = false
    add_child(_label)


# A subsystem's time-this-frame, in milliseconds. Cheap; call it every frame the
# system runs (even when the overlay is hidden — the cost is negligible).
func report(label: String, ms: float) -> void:
    var prev: float = _times[label].ms if _times.has(label) else ms
    _times[label] = { "ms": lerpf(prev, ms, SMOOTH), "frame": Engine.get_process_frames() }


func set_shown(on: bool) -> void:
    _shown = on
    _label.visible = on


func is_shown() -> bool:
    return _shown


func _process(_dt: float) -> void:
    if not _shown:
        return
    var fps := Engine.get_frames_per_second()
    var frame_ms := 1000.0 / maxf(fps, 0.001)
    var lines: Array[String] = ["FPS %.1f   (%.1f ms/frame)" % [fps, frame_ms]]
    var now := Engine.get_process_frames()
    var labels := _times.keys()
    labels.sort()
    for label in labels:
        var e: Dictionary = _times[label]
        if now - int(e.frame) > STALE_FRAMES:
            continue
        lines.append("%s  %.2f ms" % [label, e.ms])
    _label.text = "\n".join(lines)
