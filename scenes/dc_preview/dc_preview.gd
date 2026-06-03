extends Node3D

# DC prototype visual check. Mesh an analytic SDF with the GDScript Dual
# Contouring prototype and spin it. Keys: 1 sphere, 2 box, 3 wedge (same mesher,
# sharp where the field is sharp); F toggles wireframe. Open and run (F6).

const RES    := Vector3i(28, 28, 28)
const ORIGIN := Vector3.ONE * -14.0
const CELL   := 1.0

var _wireframe := false
var _shape     := 0


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

    var cam := Camera3D.new()
    cam.look_at_from_position(Vector3(18, 14, 22), Vector3.ZERO, Vector3.UP)
    add_child(cam)

    _rebuild()


func _process(delta: float) -> void:
    var surface := get_node_or_null("Surface")
    if surface != null:
        surface.rotate_y(delta * 0.4)

func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed):
        return
    match event.keycode:
        KEY_1: _shape = 0; _rebuild()
        KEY_2: _shape = 1; _rebuild()
        KEY_3: _shape = 2; _rebuild()
        KEY_F:
            _wireframe = not _wireframe
            get_viewport().debug_draw = (
                Viewport.DEBUG_DRAW_WIREFRAME if _wireframe else Viewport.DEBUG_DRAW_DISABLED)


func _rebuild() -> void:
    var sdf := _current_sdf()
    var mesh := DualContour.build_mesh(sdf, RES, ORIGIN, CELL)
    var surface := get_node_or_null("Surface") as MeshInstance3D
    if surface != null:
        surface.mesh     = mesh
        surface.rotation = Vector3.ZERO
    var arrays := mesh.surface_get_arrays(0)
    var nverts: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    var ntris: int  = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
    print("DC %s: %d vertices, %d triangles" % [_shape_name(), nverts, ntris])

func _current_sdf() -> Callable:
    match _shape:
        1:  return func(p: Vector3) -> float: return SdfShapes.box(p, Vector3.ONE * 7.0)
        2:  return func(p: Vector3) -> float: return SdfShapes.wedge(p, Vector3.ONE * 7.0)
        _:  return func(p: Vector3) -> float: return SdfShapes.sphere(p, 8.0)

func _shape_name() -> String:
    return ["sphere", "box", "wedge"][_shape]
