class_name CameraRig
extends RefCounted

const MOUSE_SENSITIVITY := 0.002

var _body: CharacterBody3D
var _head: Node3D


func _init(body: CharacterBody3D, head: Node3D) -> void:
    _body = body
    _head = head


func handle_mouse_motion(event: InputEventMouseMotion) -> void:
    _body.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
    _head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
    _head.rotation.x = clampf(_head.rotation.x, -PI * 0.5, PI * 0.5)
