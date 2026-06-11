class_name VoxelChunkBody

# A broken-off chunk of the world as a RigidBody3D. The VISUAL is a Dual-Contoured mesh
# of the chunk's OWN SDF — so it looks like what actually broke off, painted in each
# cell's material colour — while COLLISION stays a box-compound (greedy-merged AABBs;
# V-HACD off-thread is a later upgrade). The body carries its origin cells as local-space
# offsets via set_meta("cell_offsets") so StructuralIntegrity._tick_falling_bodies can tell
# when it has come to rest inside terrain and re-integrate it.
#
# The store is sampled BEFORE the caller carves the cells to air (PbdStructure._collapse
# builds the body, then writes SDF_AIR), so the mesh captures the real surface. Replaces
# the old flat-brown FallingBodyFactory boxes — same centroid / mass / cell_offsets, a real
# DC shape instead of cubes.

# Cells of air apron around the chunk's bounding box, so DC has room to close the surface
# on every side (the chunk is solid up to its own boundary; the apron is the air it cuts to).
const MARGIN := 2


static func from_voxels(voxels: Array[Vector3i], store: EditStore) -> RigidBody3D:
    var centroid  := _centroid_of(voxels)
    var voxel_set := _set_of(voxels)
    var boxes     := _greedy_merge(voxel_set)

    var body := RigidBody3D.new()
    body.position      = centroid
    body.mass          = float(voxels.size())
    body.continuous_cd = true   # fast debris vs the (thick) cooked terrain shape
    body.angular_damp  = 1.0    # settle on uneven terrain instead of rocking forever
    body.linear_damp   = 0.1
    body.set_meta("cell_offsets", _cell_offsets(voxels, centroid))

    for box in boxes:
        _add_collider(body, box.size, Vector3(box.min) + Vector3(box.size) * 0.5 - centroid)

    # One DC mesh of the chunk's masked SDF. If it came out empty (shouldn't, the cells are
    # solid), fall back to box visuals so the body is never invisible.
    var mesh := _chunk_mesh(voxels, voxel_set, store)
    if mesh != null:
        var mi := MeshInstance3D.new()
        mi.mesh              = mesh
        mi.material_override = _chunk_material()
        mi.position          = Vector3(_region_origin(voxels)) - centroid
        body.add_child(mi)
    else:
        for box in boxes:
            _add_box_visual(body, box.size, Vector3(box.min) + Vector3(box.size) * 0.5 - centroid)

    return body


# --- Chunk mesh (Dual Contouring of the masked component SDF) ---

# The chunk's bounding box grown by MARGIN, rounded up to a power-of-two octree region.
static func _region_origin(voxels: Array[Vector3i]) -> Vector3i:
    return _bounds(voxels)[0] - Vector3i.ONE * MARGIN

static func _bounds(voxels: Array[Vector3i]) -> Array:
    var lo := voxels[0]
    var hi := voxels[0]
    for v in voxels:
        lo = Vector3i(mini(lo.x, v.x), mini(lo.y, v.y), mini(lo.z, v.z))
        hi = Vector3i(maxi(hi.x, v.x), maxi(hi.y, v.y), maxi(hi.z, v.z))
    return [lo, hi]

static func _chunk_mesh(voxels: Array[Vector3i], voxel_set: Dictionary, store: EditStore) -> ArrayMesh:
    var b      := _bounds(voxels)
    var lo:  Vector3i = b[0]
    var hi:  Vector3i = b[1]
    var span := maxi(hi.x - lo.x, maxi(hi.y - lo.y, hi.z - lo.z)) + 1 + 2 * MARGIN
    var size := 1
    while size < span:
        size <<= 1
    var origin := lo - Vector3i.ONE * MARGIN
    var dim    := size + 1

    var data := store.fill_region(origin, dim, 1.0, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO)
    var idx  := store.fill_indices_region(origin, dim, 1.0)
    _mask_to_component(data, dim, origin, voxel_set)

    var depth := 0
    var n := size
    while n > 1:
        n >>= 1
        depth += 1

    var mesher := DCOctreeMesher.new()
    var arrays := mesher.mesh_clipmap(
        [data], dim, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        Vector3.ZERO, 1e9, depth, Vector3.ZERO, 0.0, 0.0, false, Vector3i.ZERO,
        [idx], MaterialPalette.colors())
    if arrays.is_empty() or (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
        return null
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


# Intersect the real field with the chunk's footprint: at each grid corner, count how many
# of its 8 surrounding cells belong to the chunk and turn that into a region SDF (8 → -0.5
# solid, 0 → +0.5 air). max() with the real field keeps the true surface where the chunk is
# and cuts a flat face at its boundary — and erases any non-chunk terrain sharing the box.
static func _mask_to_component(data: PackedFloat32Array, dim: int, origin: Vector3i, voxel_set: Dictionary) -> void:
    var corner_count: Dictionary = {}
    for cell: Vector3i in voxel_set:
        for dz in 2:
            for dy in 2:
                for dx in 2:
                    var corner := cell + Vector3i(dx, dy, dz)
                    corner_count[corner] = corner_count.get(corner, 0) + 1
    for iz in dim:
        for iy in dim:
            for ix in dim:
                var cnt: int = corner_count.get(origin + Vector3i(ix, iy, iz), 0)
                var i := ix + iy * dim + iz * dim * dim
                data[i] = maxf(data[i], 0.5 - float(cnt) / 8.0)


static func _chunk_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true   # the DC mesh paints each vertex from MaterialPalette
    mat.roughness                  = 0.85
    return mat


# --- Body scaffolding (centroid, offsets, colliders) ---

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

static func _add_box_visual(body: RigidBody3D, size: Vector3i, local_center: Vector3) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(size)
    var mi := MeshInstance3D.new()
    mi.mesh     = mesh
    mi.position = local_center
    body.add_child(mi)


# Greedy-merge the solid cells into axis-aligned boxes (the collision compound).
# See docs/architecture.md → "Greedy box merge".
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
