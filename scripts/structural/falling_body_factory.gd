class_name FallingBodyFactory

const DEBRIS_COLOR := Color(0.45, 0.30, 0.18)

# Returns an unparented RigidBody3D positioned at the component's centroid.
# Caller adds it to a parent with identity world transform (currently the
# World root). See docs/architecture.md → "Greedy box merge".
#
# The body carries its origin cells as local-space offsets via
# set_meta("cell_offsets"), so a later pass (StructuralIntegrity's
# falling-body tick) can determine whether the body has come to rest
# inside terrain SDF and react accordingly.
static func from_voxels(voxels: Array[Vector3i]) -> RigidBody3D:
    var centroid := _centroid_of(voxels)
    var boxes    := _greedy_merge(_set_of(voxels))

    var body := RigidBody3D.new()
    body.position      = centroid
    body.mass          = float(voxels.size())
    body.continuous_cd = true   # fast debris vs the (thick) cooked terrain shape
    body.angular_damp  = 1.0    # settle on uneven terrain instead of rocking forever
    body.linear_damp   = 0.1
    body.set_meta("cell_offsets", _cell_offsets(voxels, centroid))

    for box in boxes:
        var local_center := Vector3(box.min) + Vector3(box.size) * 0.5 - centroid
        _add_collider(body, box.size, local_center)
        _add_visual(  body, box.size, local_center)

    return body


static func _cell_offsets(voxels: Array[Vector3i], centroid: Vector3) -> Array[Vector3]:
    var out: Array[Vector3] = []
    for v in voxels:
        out.append(Vector3(v) + Vector3.ONE * 0.5 - centroid)
    return out


static func _centroid_of(voxels: Array[Vector3i]) -> Vector3:
    var sum := Vector3.ZERO
    for v in voxels:
        sum += Vector3(v)
    return sum / float(voxels.size()) + VoxelConstants.VOXEL_CENTER_OFFSET


static func _set_of(voxels: Array[Vector3i]) -> Dictionary:
    var out: Dictionary = {}
    for v in voxels:
        out[v] = true
    return out


static func _add_collider(body: RigidBody3D, size: Vector3i, local_center: Vector3) -> void:
    var shape := BoxShape3D.new()
    shape.size = Vector3(size)

    var collider := CollisionShape3D.new()
    collider.shape    = shape
    collider.position = local_center

    body.add_child(collider)


static func _add_visual(body: RigidBody3D, size: Vector3i, local_center: Vector3) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(size)

    var mat := StandardMaterial3D.new()
    mat.albedo_color = DEBRIS_COLOR

    var mi := MeshInstance3D.new()
    mi.mesh              = mesh
    mi.position          = local_center
    mi.material_override = mat

    body.add_child(mi)


static func _greedy_merge(voxel_set: Dictionary) -> Array:
    var consumed: Dictionary = {}
    var boxes:    Array      = []

    var keys: Array = voxel_set.keys()
    keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
        if a.y != b.y: return a.y < b.y
        if a.z != b.z: return a.z < b.z
        return a.x < b.x)

    for start: Vector3i in keys:
        if consumed.has(start):
            continue

        var sx := 1
        while voxel_set.has(start + Vector3i(sx, 0, 0)) \
                and not consumed.has(start + Vector3i(sx, 0, 0)):
            sx += 1

        var sz := 1
        while true:
            var z_ok := true
            for dx in range(sx):
                var p := start + Vector3i(dx, 0, sz)
                if not voxel_set.has(p) or consumed.has(p):
                    z_ok = false
                    break
            if not z_ok:
                break
            sz += 1

        var sy := 1
        while true:
            var y_ok := true
            for dx in range(sx):
                for dz in range(sz):
                    var p := start + Vector3i(dx, sy, dz)
                    if not voxel_set.has(p) or consumed.has(p):
                        y_ok = false
                        break
                if not y_ok:
                    break
            if not y_ok:
                break
            sy += 1

        for dx in range(sx):
            for dy in range(sy):
                for dz in range(sz):
                    consumed[start + Vector3i(dx, dy, dz)] = true

        boxes.append({
            "min":  start,
            "size": Vector3i(sx, sy, sz),
        })

    return boxes
