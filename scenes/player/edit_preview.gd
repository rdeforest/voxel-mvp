extends MeshInstance3D

var player: Node  # set by player._ready()

func _process(_delta: float) -> void:
    if player == null:
        return

    var rc: RayCast3D = player.raycast
    if not rc.is_colliding():
        visible = false
        return

    visible = true
    var hit_pos    := rc.get_collision_point()
    var hit_normal := rc.get_collision_normal()

    var mode: EditMode = player.current_mode()

    mesh              = mode.get_preview_mesh.call(hit_pos, hit_normal)
    material_override = mode.get_preview_material.call(hit_pos, hit_normal)
    global_position   = mode.get_preview_position.call(hit_pos, hit_normal)

    if mode.get_preview_basis.is_valid():
        global_transform.basis = mode.get_preview_basis.call(hit_pos, hit_normal)
    else:
        global_transform.basis = Basis.IDENTITY
