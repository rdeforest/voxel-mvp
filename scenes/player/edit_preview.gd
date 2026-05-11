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
    var hit_pos        := rc.get_collision_point()
    var hit_normal     := rc.get_collision_normal()

    var mode: EditMode  = player.current_mode()

    mesh              = mode.get_preview_mesh.call(hit_pos, hit_normal)
    material_override = mode.get_preview_material.call(hit_pos, hit_normal)
    global_position   = mode.get_preview_position.call(hit_pos, hit_normal)

    # Align plane to surface normal for flatten
    if mesh is PlaneMesh:
        var preview_normal: Vector3 = player._get_flatten_normal()
        if preview_normal == Vector3.ZERO:
            preview_normal = hit_normal
        _align_to_normal(preview_normal)

    else:
        global_transform.basis = Basis.IDENTITY

func _align_to_normal(normal: Vector3) -> void:
    if normal.is_equal_approx(Vector3.UP):
        global_transform.basis = Basis.IDENTITY

    elif normal.is_equal_approx(Vector3.DOWN):
        global_transform.basis = Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.FORWARD)

    else:
        var up      := normal
        var right   := up   .cross(Vector3.UP).normalized()
        var forward := right.cross(up)        .normalized()

        global_transform.basis = Basis(right, up, forward)
