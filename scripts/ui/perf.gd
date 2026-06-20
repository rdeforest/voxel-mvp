extends ToolWindow

# Performance HUD (autoload `Perf`) — a draggable paper card, console-toggled (`perf`). Shows
# FPS + frame time, plus per-subsystem time-per-frame: a system wraps its work and calls
# Perf.report("Name", ms) each frame. Entries not reported for a while drop off (e.g. when a
# subsystem is toggled off). Below the text, a frame-time graph: one bar per recent frame,
# height = frame time, colour = severity bucket (the bars stay colour-coded — that's data, not
# decoration); a blue tick marks the frame a new terrain mesh was applied (mark_event), so re-mesh
# spikes are visible as such. Never captures input; records every frame even while paused/hidden
# so no spike is missed. Drag the title bar with the mouse free (F10 / console open).

const STALE_FRAMES := 30
const SMOOTH := 0.15           # EMA factor for readability

# Frame-time graph: GRAPH_CAP bars across a GRAPH_W × GRAPH_H panel inside the card. A bar at full
# height means >= FULL_MS; the colour says how bad.
const GRAPH_CAP := 256         # frames of history (bars)
const GRAPH_W   := 256.0       # graph panel width  (px)
const GRAPH_H   := 64.0        # graph panel height (px)
const FULL_MS   := 34.0        # frame time that fills a bar to the top
const _LIMITS   := [8.0, 16.0, 34.0, 100.0]
const _GREEN    := Color(0.25, 0.90, 0.35)
const _YELLOW   := Color(0.95, 0.90, 0.20)
const _ORANGE   := Color(1.00, 0.60, 0.12)
const _RED      := Color(0.92, 0.18, 0.18)
const _WHITE    := Color(1.0, 1.0, 1.0)
const _COLORS   := [_GREEN, _YELLOW, _ORANGE, _RED]   # parallel to _LIMITS; over 100ms -> _WHITE

var _times: Dictionary = {}    # label -> {ms: float, frame: int}
var _status: Dictionary = {}   # key  -> {text: String, frame: int} — non-timing state (queue sizes, blockers)
var _label: Label
var _shown := false
var _last_physics_frame := 0

var _frames: PackedFloat32Array = PackedFloat32Array()   # ring of recent frame times (ms)
var _marks: PackedByteArray = PackedByteArray()           # parallel: 1 = mesh applied that frame
var _pending_mark := false
var _drawer: Control
var _last_gen_ms := 0.0                                   # last frame-gen cost (cap-independent); read by the DC budget controller

const QUEUE_GRAPH_H := 40.0                               # refine-queue graph height (px)
const _CYAN := Color(0.30, 0.80, 0.95)
var _queue: PackedFloat32Array = PackedFloat32Array()     # ring of recent refine-queue sizes (parallel to _frames)
var _last_queue := 0.0                                    # latest reported refine-queue depth (held between grows)
var _queue_drawer: Control


# A drawing surface that defers to a host-supplied draw callback (keeps every graph in this one file).
class Strip extends Control:
    var draw_fn: Callable
    func _draw() -> void:
        if draw_fn.is_valid():
            draw_fn.call(self)


func _ready() -> void:
    window_id    = "perf"
    window_title = "Performance"
    set_fraction(Vector2(0.66, 0.52))
    process_mode = Node.PROCESS_MODE_ALWAYS   # record + toggle while the tree is paused
    super._ready()

    _label = Label.new()
    _label.add_theme_font_override("font", ThemeDB.fallback_font)
    _label.add_theme_font_size_override("font_size", 14)
    _label.add_theme_color_override("font_color", INK)
    content.add_child(_label)

    _drawer = Strip.new()
    _drawer.draw_fn             = _draw_graph
    _drawer.custom_minimum_size = Vector2(GRAPH_W, GRAPH_H)
    _drawer.mouse_filter        = Control.MOUSE_FILTER_IGNORE
    content.add_child(_drawer)

    _queue_drawer = Strip.new()
    _queue_drawer.draw_fn             = _draw_queue_graph
    _queue_drawer.custom_minimum_size = Vector2(GRAPH_W, QUEUE_GRAPH_H)
    _queue_drawer.mouse_filter        = Control.MOUSE_FILTER_IGNORE
    content.add_child(_queue_drawer)

    # Measure the ACTUAL per-frame render cost (CPU + GPU), which is independent of vsync / fps_max — the
    # display interval (get_frames_per_second) clamps to the cap and can't show work below it.
    RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

    visible = false


# A subsystem's time-this-frame, in milliseconds. Cheap; call it every frame the
# system runs (even when the overlay is hidden — the cost is negligible).
func report(label: String, ms: float) -> void:
    var prev: float = _times[label].ms if _times.has(label) else ms
    _times[label] = { "ms": lerpf(prev, ms, SMOOTH), "frame": Engine.get_process_frames() }


# The current refine-queue depth (leaves still wanting sharpening). Held between grows and graphed per frame.
func report_queue(depth: int) -> void:
    _last_queue = float(depth)


func set_shown(on: bool) -> void:
    _shown = on
    visible = on


func is_shown() -> bool:
    return _shown


# A line of non-timing state (queue depth, what a worker is blocked on, …). Shown under the
# timings; stale entries drop off like report()'s. Call every frame the state is meaningful.
func status(key: String, text: String) -> void:
    _status[key] = { "text": text, "frame": Engine.get_process_frames() }


# Flag that a one-off event (a terrain mesh apply) happened this frame; the graph ticks it.
func mark_event() -> void:
    _pending_mark = true


func _process(_dt: float) -> void:
    # Record the ACTUAL frame-generation cost every frame (cheap; even while hidden so history is ready).
    # This is the work to make a frame — NOT the display interval, which vsync/fps_max clamp.
    var gpu_ms := _gpu_ms()
    var proc_ms := _process_ms()
    var render_cpu_ms := _render_cpu_ms()
    # Frame-gen = the render cost (CPU submit + GPU), the two signals that DON'T change with the cap.
    # proc (TIME_PROCESS) is deliberately NOT folded in: under vsync the main thread stalls on frame
    # pacing / present backpressure and that lands in the process-step timing (proc balloons while
    # render-cpu + GPU stay put), so it isn't clean work. It's shown separately, labelled. Main-thread
    # game work here is minor anyway — the mesher runs off-thread (mesh-lag, not proc) — so render-cpu
    # + GPU is the real per-frame cost.
    var gen_ms := maxf(render_cpu_ms, gpu_ms)
    _last_gen_ms = gen_ms
    _frames.append(gen_ms)
    _marks.append(1 if _pending_mark else 0)
    _pending_mark = false
    _queue.append(_last_queue)
    if _frames.size() > GRAPH_CAP:
        _frames.remove_at(0)
        _marks.remove_at(0)
    if _queue.size() > GRAPH_CAP:
        _queue.remove_at(0)
    if not _shown:
        return
    _drawer.queue_redraw()
    _queue_drawer.queue_redraw()
    var fps := Engine.get_frames_per_second()
    var now := Engine.get_process_frames()
    var ticks := Engine.get_physics_frames() - _last_physics_frame
    _last_physics_frame = Engine.get_physics_frames()
    var lines: Array[String] = [
        "frame gen %.2f ms  (render-cpu %.2f / GPU %.2f)   proc %.2f (+present-wait under vsync)" % [gen_ms, render_cpu_ms, gpu_ms, proc_ms],
        "FPS %.1f (display, capped)   phys %d ticks/frame" % [fps, ticks],
    ]
    var labels := _times.keys()
    labels.sort()
    var cpu_sum := 0.0
    for label in labels:
        var e: Dictionary = _times[label]
        if now - int(e.frame) > STALE_FRAMES:
            continue
        cpu_sum += e.ms
        lines.append("%s  %.2f ms" % [label, e.ms])
    # Accounted CPU vs the whole frame: a large, bouncing "other" with small/steady CPU means the
    # cost is GPU / present / unmeasured — not in any timed subsystem (look at the shaders, not here).
    lines.append("Σ CPU %.2f ms   |   other %.2f ms" % [cpu_sum, maxf(0.0, gen_ms - cpu_sum)])
    lines.append("refine queue %d leaves (cyan graph)" % int(_last_queue))
    var keys := _status.keys()
    keys.sort()
    for key in keys:
        var s: Dictionary = _status[key]
        if now - int(s.frame) > STALE_FRAMES:
            continue
        lines.append("%s: %s" % [key, s.text])
    _label.text = "\n".join(lines)


# GPU time to render the last frame, in ms (cap-independent — GPU execution, measured by the render server).
func _gpu_ms() -> float:
    return RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())


# Main-thread compute this frame, in ms (the _process step). Cap-independent: the fps_max throttle is a
# post-frame sleep and vsync blocks the render thread — neither is counted here.
func _process_ms() -> float:
    return Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0


# Render-server CPU time to build + submit the frame, in ms. NOT cap-independent: under vsync the render
# thread blocks acquiring the next swapchain image (the present-wait), and that block is counted here — so
# this rises under vsync though the work is unchanged. Shown for info; kept out of the frame-gen estimate.
func _render_cpu_ms() -> float:
    return RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())


# The last frame's cap-independent generation cost (max of render-CPU and GPU), in ms. The DC budget
# controller reads this for its frame-headroom gate so it isn't fooled by the vsync-capped display dt.
func frame_gen_ms() -> float:
    return _last_gen_ms


func _frame_color(ms: float) -> Color:
    for i in _LIMITS.size():
        if ms < _LIMITS[i]:
            return _COLORS[i]
    return _WHITE


# Called by the Strip child. Draws the frame-time graph across the drawer's own rect (oldest bar
# left, newest right). Bars stand on a faint dark backdrop so the colours read on the paper card.
func _draw_graph(c: Control) -> void:
    var control_size := c.size
    var bw := control_size.x / float(GRAPH_CAP)
    c.draw_rect(Rect2(Vector2.ZERO, control_size), Color(0.0, 0.0, 0.0, 0.30))
    for ms in _LIMITS:                                   # faint reference lines at 8/16/34/100
        var ry := control_size.y - clampf(ms / FULL_MS, 0.0, 1.0) * control_size.y
        c.draw_line(Vector2(0.0, ry), Vector2(control_size.x, ry), Color(1.0, 1.0, 1.0, 0.12))
    var n := _frames.size()
    for i in n:
        var ms := _frames[i]
        var h := clampf(ms / FULL_MS, 0.0, 1.0) * control_size.y
        var x := i * bw
        c.draw_rect(Rect2(x, control_size.y - h, maxf(bw, 1.0), h), _frame_color(ms))
        if _marks[i] != 0:
            c.draw_line(Vector2(x, 0.0), Vector2(x, control_size.y), Color(0.40, 0.70, 1.0, 0.85), 1.0)


# Refine-queue graph (cyan): recent backlog depth, auto-scaled to the window's own peak so the TREND reads —
# bars sloping down = the worker is draining the work it found (progress); flat = treading water; rising = it's
# finding work faster than it clears. The exact count is in the text line above; this is the shape over time.
func _draw_queue_graph(c: Control) -> void:
    var control_size := c.size
    c.draw_rect(Rect2(Vector2.ZERO, control_size), Color(0.0, 0.0, 0.0, 0.30))
    var n := _queue.size()
    if n == 0:
        return
    var peak := 1.0
    for q in _queue:
        peak = maxf(peak, q)
    var bw := control_size.x / float(GRAPH_CAP)
    for i in n:
        var h := (_queue[i] / peak) * control_size.y
        c.draw_rect(Rect2(i * bw, control_size.y - h, maxf(bw, 1.0), h), _CYAN)
