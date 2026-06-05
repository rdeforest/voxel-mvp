extends CanvasLayer

# Fading toast notifications in the top-right corner (autoload `Toast`). Call from
# anywhere: Toast.success("Saved."), Toast.failure("..."), or Toast.show_message(
# text, color). Messages stack newest-on-top and fade out after a hold. Never
# captures input (everything is MOUSE_FILTER_IGNORE), so the game plays through it,
# and it animates while paused so a "Saved." still shows from a pause menu.

const HOLD_SECONDS := 2.5
const FADE_SECONDS := 1.0
const WIDTH        := 420.0
const MARGIN       := 12.0

const SUCCESS := Color(0.55, 1.0, 0.55)
const FAILURE := Color(1.0, 0.5, 0.4)
const INFO    := Color(0.92, 0.92, 0.92)

var _box: VBoxContainer


func _ready() -> void:
    layer = 128                                       # above the game HUD
    process_mode = Node.PROCESS_MODE_ALWAYS           # animate even when paused
    _box = VBoxContainer.new()
    _box.anchor_left = 1.0
    _box.anchor_top = 0.0
    _box.anchor_right = 1.0
    _box.anchor_bottom = 0.0
    _box.offset_left = -WIDTH - MARGIN
    _box.offset_right = -MARGIN
    _box.offset_top = MARGIN
    _box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    _box.grow_vertical = Control.GROW_DIRECTION_END
    _box.alignment = BoxContainer.ALIGNMENT_BEGIN
    _box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_box)


func show_message(text: String, color := INFO) -> void:
    var label := Label.new()
    label.text = text
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
    label.add_theme_constant_override("outline_size", 5)
    label.add_theme_font_size_override("font_size", 18)
    _box.add_child(label)
    _box.move_child(label, 0)                          # newest on top
    var tween := create_tween()
    tween.tween_interval(HOLD_SECONDS)
    tween.tween_property(label, "modulate:a", 0.0, FADE_SECONDS)
    tween.tween_callback(label.queue_free)


func success(text: String) -> void:
    show_message(text, SUCCESS)

func failure(text: String) -> void:
    show_message(text, FAILURE)
