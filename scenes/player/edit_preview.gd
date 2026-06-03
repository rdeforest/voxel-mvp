extends MeshInstance3D

var player: Node  # set by player._ready()

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
