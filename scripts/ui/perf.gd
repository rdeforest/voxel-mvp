extends CanvasLayer

# Performance HUD (autoload `Perf`), bottom-right, console-toggled (`perf`). Shows
# FPS + frame time, plus per-subsystem time-per-frame: a system wraps its work and
# calls Perf.report("Name", ms) each frame. Entries not reported for a while drop
# off (e.g. when a subsystem is toggled off). Never captures input; runs while paused.

const STALE_FRAMES := 30
const SMOOTH := 0.15           # EMA factor for readability

# Frame-time graph (bottom strip): one bar per recent frame, height = frame time, colour
# = severity bucket. A bar at full height means >= FULL_MS; the colour says how bad. A
# blue tick marks the frame a new terrain mesh was applied (Perf.mark_event), so re-mesh
# spikes are visible as such.
const GRAPH_CAP := 256         # frames of history (bars)
const GRAPH_H   := 64.0        # strip height (px)
const FULL_MS   := 34.0        # frame time that fills a bar to the top
const _LIMITS   := [8.0, 16.0, 34.0, 100.0]
const _GREEN    := Color(0.25, 0.90, 0.35)
const _YELLOW   := Color(0.95, 0.90, 0.20)
const _ORANGE   := Color(1.00, 0.60, 0.12)
const _RED      := Color(0.92, 0.18, 0.18)
const _WHITE    := Color(1.0, 1.0, 1.0)
const _COLORS   := [_GREEN, _YELLOW, _ORANGE, _RED]   # parallel to _LIMITS; over 100ms -> _WHITE

var _times: Dictionary = {}    # label -> {ms: float, frame: int}
var _label: Label
var _shown := false
var _last_physics_frame := 0

var _frames: PackedFloat32Array = PackedFloat32Array()   # ring of recent frame times (ms)
var _marks: PackedByteArray = PackedByteArray()           # parallel: 1 = mesh applied that frame
var _pending_mark := false
var _drawer: Control


# A drawing surface that defers back to the host Perf layer (keeps everything in one file).
class Strip extends Control:
    var host
    func _draw() -> void:
        host._draw_graph(self)


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

    _drawer = Strip.new()
    _drawer.host = self
    _drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
    _drawer.visible = false

    # Order matters: later siblings draw on top. Add the graph first (behind) and the
    # text last (on top), so the bottom strip never covers the perf readout it overlaps.
    add_child(_drawer)
    add_child(_label)


# A subsystem's time-this-frame, in milliseconds. Cheap; call it every frame the
# system runs (even when the overlay is hidden — the cost is negligible).
func report(label: String, ms: float) -> void:
    var prev: float = _times[label].ms if _times.has(label) else ms
    _times[label] = { "ms": lerpf(prev, ms, SMOOTH), "frame": Engine.get_process_frames() }


func set_shown(on: bool) -> void:
    _shown = on
    _label.visible = on
    _drawer.visible = on


func is_shown() -> bool:
    return _shown


# Flag that a one-off event (a terrain mesh apply) happened this frame; the graph ticks it.
func mark_event() -> void:
    _pending_mark = true


func _process(dt: float) -> void:
    # Record every frame (cheap) so the history is already there when the overlay is shown
    # and no spike is missed. dt is the real frame interval — the spike signal we want.
    _frames.append(dt * 1000.0)
    _marks.append(1 if _pending_mark else 0)
    _pending_mark = false
    if _frames.size() > GRAPH_CAP:
        _frames.remove_at(0)
        _marks.remove_at(0)
    if not _shown:
        return
    _drawer.queue_redraw()
    var fps := Engine.get_frames_per_second()
    var frame_ms := 1000.0 / maxf(fps, 0.001)
    var now := Engine.get_process_frames()
    var ticks := Engine.get_physics_frames() - _last_physics_frame
    _last_physics_frame = Engine.get_physics_frames()
    var lines: Array[String] = [
        "FPS %.1f   (%.1f ms/frame)" % [fps, frame_ms],
        "phys %d ticks/frame" % ticks,   # >1 = physics over budget, catching up
    ]
    var labels := _times.keys()
    labels.sort()
    for label in labels:
        var e: Dictionary = _times[label]
        if now - int(e.frame) > STALE_FRAMES:
            continue
        lines.append("%s  %.2f ms" % [label, e.ms])
    _label.text = "\n".join(lines)


func _frame_color(ms: float) -> Color:
    for i in _LIMITS.size():
        if ms < _LIMITS[i]:
            return _COLORS[i]
    return _WHITE


# Called by the Strip child. Draws the bottom frame-time strip into `c` (full-rect, so its
# size is the viewport). Bars run oldest (left) to newest (right).
func _draw_graph(c: Control) -> void:
    var size := c.size
    var w := size.x
    var top := size.y - GRAPH_H
    var bw := w / float(GRAPH_CAP)
    c.draw_rect(Rect2(0.0, top, w, GRAPH_H), Color(0.0, 0.0, 0.0, 0.45))
    for ms in _LIMITS:                                   # faint reference lines at 8/16/34/100
        var ry := size.y - clampf(ms / FULL_MS, 0.0, 1.0) * GRAPH_H
        c.draw_line(Vector2(0.0, ry), Vector2(w, ry), Color(1.0, 1.0, 1.0, 0.10))
    var n := _frames.size()
    for i in n:
        var ms := _frames[i]
        var h := clampf(ms / FULL_MS, 0.0, 1.0) * GRAPH_H
        var x := i * bw
        c.draw_rect(Rect2(x, size.y - h, maxf(bw, 1.0), h), _frame_color(ms))
        if _marks[i] != 0:
            c.draw_line(Vector2(x, top), Vector2(x, size.y), Color(0.40, 0.70, 1.0, 0.85), 1.0)
