class_name PlayerMovement
extends RefCounted

const SPEED         := 8.0
const JUMP_VELOCITY := 9.0

var _body:    CharacterBody3D
var _gravity: float


func _init(body: CharacterBody3D) -> void:
    _body    = body
    _gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


func tick(delta: float) -> void:
    if not _body.is_on_floor():
        _body.velocity.y -= _gravity * delta

    # Shift is reserved as a modifier for input chords (e.g. placement
    # adjustment in Build mode). When Shift is held we don't read the
    # WASD-bound movement inputs at all — Shift+W is a distinct input,
    # not "walk forward AND something else."
    var chord_active := Input.is_key_pressed(KEY_SHIFT)

    if not chord_active and Input.is_action_just_pressed("ui_accept") and _body.is_on_floor():
        _body.velocity.y = JUMP_VELOCITY

    var direction := Vector3.ZERO
    if not chord_active:
        var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
        direction = (_body.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

    if direction:
        _body.velocity.x = direction.x * SPEED
        _body.velocity.z = direction.z * SPEED
    else:
        _body.velocity.x = move_toward(_body.velocity.x, 0, SPEED)
        _body.velocity.z = move_toward(_body.velocity.z, 0, SPEED)

    _body.move_and_slide()
