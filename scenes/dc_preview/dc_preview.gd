extends Node3D

# DC prototype viewer. Mesh an analytic SDF with the GDScript Dual Contouring
# prototype and inspect it with an orbit camera.
#
#   drag (left mouse) : orbit        wheel : zoom
#   1 sphere  2 box  3 wedge  (same mesher, sharp where the field is sharp)
#   F : wireframe
#
# Open and run with F6.

const RES    := Vector3i(28, 28, 28)
const ORIGIN := Vector3.ONE * -14.0
const CELL   := 1.0

var _yaw   := 0.6
var _pitch := 0.5
var _dist  := 34.0
var _dragging  := false
var _wireframe := false
var _shape     := 0

var _cam: Camera3D


func _ready() -> void:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.55, 0.65, 0.85)
    mat.roughness    = 0.6

    var surface := MeshInstance3D.new()
    surface.name              = "Surface"
    surface.material_override  = mat
    add_child(surface)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-50, -40, 0)
    add_child(light)

    _cam = Camera3D.new()
    add_child(_cam)
    _update_camera()

    print("DC viewer — drag to orbit, wheel to zoom, 1/2/3 shapes, F wireframe")
    _rebuild()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                _dragging = event.pressed
            MOUSE_BUTTON_WHEEL_UP:
                if event.pressed:
                    _dist = maxf(6.0, _dist - 2.0)
                    _update_camera()
            MOUSE_BUTTON_WHEEL_DOWN:
                if event.pressed:
                    _dist = minf(120.0, _dist + 2.0)
                    _update_camera()
        return

    if event is InputEventMouseMotion and _dragging:
        _yaw   -= event.relative.x * 0.01
        _pitch  = clampf(_pitch + event.relative.y * 0.01, -1.4, 1.4)
        _update_camera()
        return

    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_1: _shape = 0; _rebuild()
            KEY_2: _shape = 1; _rebuild()
            KEY_3: _shape = 2; _rebuild()
            KEY_F:
                _wireframe = not _wireframe
                get_viewport().debug_draw = (
                    Viewport.DEBUG_DRAW_WIREFRAME if _wireframe else Viewport.DEBUG_DRAW_DISABLED)


func _update_camera() -> void:
    var dir := Vector3(
        cos(_pitch) * sin(_yaw),
        sin(_pitch),
        cos(_pitch) * cos(_yaw))
    _cam.look_at_from_position(dir * _dist, Vector3.ZERO, Vector3.UP)


func _rebuild() -> void:
    var mesh := DualContour.build_mesh(_current_sdf(), RES, ORIGIN, CELL)
    var surface := get_node_or_null("Surface") as MeshInstance3D
    if surface != null:
        surface.mesh = mesh
    var arrays := mesh.surface_get_arrays(0)
    var nverts: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    var ntris: int  = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
    print("DC %s: %d vertices, %d triangles" % [_shape_name(), nverts, ntris])

func _current_sdf() -> Callable:
    # Off-grid extents (6.7, not 7.0) so faces don't land on integer grid planes.
    match _shape:
        1:  return func(p: Vector3) -> float: return SdfShapes.box(p, Vector3.ONE * 6.7)
        2:  return func(p: Vector3) -> float: return SdfShapes.wedge(p, Vector3.ONE * 6.7)
        _:  return func(p: Vector3) -> float: return SdfShapes.sphere(p, 8.0)

func _shape_name() -> String:
    return ["sphere", "box", "wedge"][_shape]
