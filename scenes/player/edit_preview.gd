extends MeshInstance3D

var player: Node  # set by player._ready()

# Child stick marking the CSG resize axis. A child of this node, so it inherits
# the ghost's rotation basis automatically; we only orient it along the active
# LOCAL axis direction the EditMode reports.
const ARROW_LEN := 3.0
var _arrow: MeshInstance3D


func _ready() -> void:
    var stick := CylinderMesh.new()
    stick.top_radius    = 0.12
    stick.bottom_radius = 0.12
    stick.height        = ARROW_LEN
    var mat := StandardMaterial3D.new()
    mat.albedo_color  = Color(1.0, 0.95, 0.2)
    mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.no_depth_test = true   # show through the translucent ghost
    _arrow = MeshInstance3D.new()
    _arrow.mesh              = stick
    _arrow.material_override = mat
    _arrow.visible           = false
    add_child(_arrow)


func _process(_delta: float) -> void:
    if player == null:
        return

    var mode: EditMode = player.current_activity()
    if mode == null:
        visible = false
        return

    var aim: Aim = player.current_target()
    if aim == null:
        visible = false
        return

    visible = true
    mesh              = mode.get_preview_mesh.call(aim.position, aim.normal)
    material_override = mode.get_preview_material.call(aim.position, aim.normal)
    global_position   = mode.get_preview_position.call(aim.position, aim.normal)

    if mode.get_preview_basis.is_valid():
        global_transform.basis = mode.get_preview_basis.call(aim.position, aim.normal)
    else:
        global_transform.basis = Basis.IDENTITY

    _update_arrow(mode)


# Orient the resize-axis stick along the EditMode's local axis direction, sitting
# from the ghost centre outward. Hidden when the mode reports no axis (or none).
func _update_arrow(mode: EditMode) -> void:
    if not mode.get_axis_arrow.is_valid():
        _arrow.visible = false
        return
    var dir: Vector3 = mode.get_axis_arrow.call()
    if dir == Vector3.ZERO:
        _arrow.visible = false
        return
    _arrow.visible = true
    var quat := Quaternion(Vector3.UP, dir.normalized())
    _arrow.transform = Transform3D(Basis(quat), dir.normalized() * (ARROW_LEN * 0.5))
