extends Node3D

# Bite A visual check: mesh an analytic sphere with the GDScript Dual Contouring
# prototype and spin it. F toggles wireframe so the off-grid triangle structure
# is visible. Open this scene and run it (F6).

const R   := 8.0
const RES := Vector3i(24, 24, 24)

var _wireframe := false


func _ready() -> void:
    var sdf := func(p: Vector3) -> float: return p.length() - R
    var mesh := DualContour.build_mesh(sdf, RES, Vector3.ONE * -12.0, 1.0)

    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.55, 0.65, 0.85)
    mat.roughness    = 0.6

    var surface := MeshInstance3D.new()
    surface.name             = "Surface"
    surface.mesh             = mesh
    surface.material_override = mat
    add_child(surface)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-50, -40, 0)
    add_child(light)

    var cam := Camera3D.new()
    cam.position = Vector3(0, 6, 26)
    cam.look_at_from_position(cam.position, Vector3.ZERO, Vector3.UP)
    add_child(cam)

    var arrays := mesh.surface_get_arrays(0)
    var nverts: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    var ntris: int  = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
    print("DC sphere: %d vertices, %d triangles" % [nverts, ntris])


func _process(delta: float) -> void:
    var surface := get_node_or_null("Surface")
    if surface != null:
        surface.rotate_y(delta * 0.5)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_F:
        _wireframe = not _wireframe
        get_viewport().debug_draw = (
            Viewport.DEBUG_DRAW_WIREFRAME if _wireframe else Viewport.DEBUG_DRAW_DISABLED)
