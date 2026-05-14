class_name CollapseDetector
extends RefCounted

# Detects connected components of unsupported voxels and converts them
# into falling rigid bodies. Designed to be invoked by StructuralIntegrity
# after its dirty queue settles.
#
# A voxel is a "fall candidate" when its support has decayed to (effectively)
# zero. We flood-fill across candidate voxels to find connected components,
# extract each as a rigid body, and clear the source voxels from the terrain.

# A single component-in-progress carried across frames if the flood
# exceeds the budget.
var _pending_floods: Array = []  # of { voxels: Array[Vector3i], frontier: Array[Vector3i], visited: Dictionary }

# Coordinates already claimed by a finalized or in-progress flood this pass,
# so a second scan doesn't re-flood the same mass.
var _claimed: Dictionary = {}

# Back-reference to the integrity manager (provides voxel_data, terrain,
# and voxel removal helpers).
var _integrity: Node


func _init(integrity: Node) -> void:
    _integrity = integrity


# Called by StructuralIntegrity once the propagation dirty_queue is empty.
# Returns true if any collapses were materialized this call.
func step() -> bool:
    # 1. Continue any flood that didn't finish last frame.
    var progressed := false
    while not _pending_floods.is_empty():
        var flood: Dictionary = _pending_floods[0]
        var finished := _advance_flood(flood, VoxelConstants.DETECTION_BUDGET)
        if finished:
            _pending_floods.pop_front()
            if not flood.voxels.is_empty():
                _materialize_collapse(flood.voxels)
                progressed = true
        else:
            # Budget exhausted this frame; resume next frame.
            return progressed

    # 2. Scan for new fall candidates and start new floods.
    for pos in _integrity.voxel_data.keys():
        if _claimed.has(pos):
            continue
        if not _is_fall_candidate(pos):
            continue

        var flood := {
            "voxels":   [] as Array,
            "frontier": [pos] as Array,
            "visited":  { pos: true },
        }
        _claimed[pos] = true

        var finished := _advance_flood(flood, VoxelConstants.DETECTION_BUDGET)
        if finished:
            if not flood.voxels.is_empty():
                _materialize_collapse(flood.voxels)
                progressed = true
        else:
            _pending_floods.append(flood)
            return progressed  # ran out of budget; pick up next frame

    # 3. Reset claim set for the next propagation/detection cycle.
    _claimed.clear()
    return progressed


# Advance one flood by up to `budget` voxels. Returns true when the
# flood is complete (frontier is empty).
func _advance_flood(flood: Dictionary, budget: int) -> bool:
    var voxels:   Array      = flood.voxels
    var frontier: Array      = flood.frontier
    var visited:  Dictionary = flood.visited

    var processed := 0
    while not frontier.is_empty() and processed < budget:
        var pos: Vector3i = frontier.pop_back()
        voxels.append(pos)
        _claimed[pos] = true
        processed += 1

        for neighbor in _neighbors(pos):
            if visited.has(neighbor):
                continue
            # We only flood across other fall candidates. Boundaries
            # (supported tracked voxels, solid terrain, air) terminate
            # the expansion at this neighbor.
            if not _integrity.voxel_data.has(neighbor):
                continue
            if not _is_fall_candidate(neighbor):
                continue
            visited[neighbor] = true
            frontier.append(neighbor)

    return frontier.is_empty()


func _is_fall_candidate(pos: Vector3i) -> bool:
    if not _integrity.voxel_data.has(pos):
        return false
    var data: Dictionary = _integrity.voxel_data[pos]
    if data.dirty:
        return false  # propagation isn't done with this voxel yet
    return data.support <= VoxelConstants.FALL_THRESHOLD


func _neighbors(pos: Vector3i) -> Array:
    return [
        pos + Vector3i( 1,  0,  0),
        pos + Vector3i(-1,  0,  0),
        pos + Vector3i( 0,  1,  0),
        pos + Vector3i( 0, -1,  0),
        pos + Vector3i( 0,  0,  1),
        pos + Vector3i( 0,  0, -1),
    ]


# Take a connected component of unsupported voxels and turn it into a falling
# rigid body. For v0.0 we use greedy axis-aligned box merge for collision and
# a simple BoxMesh-per-merged-box for visuals. (We can switch to slicing the
# existing voxel mesh later; that's a polish pass.)
func _materialize_collapse(voxels: Array) -> void:
    # Compute centroid (used to position the rigid body's origin).
    var centroid := Vector3.ZERO
    for v in voxels:
        centroid += Vector3(v)
    centroid /= float(voxels.size())
    # Voxel-grid cells are VOXEL_SIZE meters; offset to cell center.
    centroid += VoxelConstants.VOXEL_CENTER_OFFSET

    # Greedy merge into the minimum set of axis-aligned boxes.
    var voxel_set: Dictionary = {}
    for v in voxels:
        voxel_set[v] = true
    var boxes := _greedy_merge_boxes(voxel_set)

    # Build the rigid body.
    var body := RigidBody3D.new()
    body.global_position = centroid

    # Mass scales with voxel count (1kg per voxel for now; revisit per-material).
    body.mass = float(voxels.size())

    body.can_sleep = false

    for box in boxes:
        # box is { min: Vector3i, size: Vector3i }
        var box_center_local := Vector3(box.min) + Vector3(box.size) * 0.5 - centroid

        var shape := BoxShape3D.new()
        shape.size = Vector3(box.size)
        var collider := CollisionShape3D.new()
        collider.shape = shape
        collider.position = box_center_local
        body.add_child(collider)

        var mesh := BoxMesh.new()
        mesh.size = Vector3(box.size)
        var mi := MeshInstance3D.new()
        mi.mesh = mesh
        mi.position = box_center_local
        # Visual: brown-ish so we can see it falling. Real material color TBD.
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color(0.45, 0.30, 0.18)
        mi.material_override = mat
        body.add_child(mi)

    # Parent into the world (sibling of the terrain).
    _integrity.get_parent().add_child(body)

    # Clear the source voxels from the SDF terrain and the integrity tracker.
    # This will dirty neighbors and may trigger cascading collapses next pass.
    var voxel_tool: VoxelTool = _integrity.terrain.get_voxel_tool()
    voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
    voxel_tool.mode = VoxelTool.MODE_REMOVE
    for v in voxels:
        # Set SDF positive (air) at each cell. do_sphere with radius < 1
        # would be approximate; set_voxel_f is exact.
        # We set the value to 5 to account for the interpolation of the SDF value.
        voxel_tool.set_voxel_f(v, VoxelConstants.SDF_AIR)
        _integrity.remove_voxel(v)


# Greedy axis-aligned box merge. Walks voxels in scan order, grows each
# starting voxel as far as it can in +X, then +Y, then +Z while all cells
# in the candidate box are members of the set and not yet consumed.
# Not optimal, but produces a small number of boxes for slab-shaped masses.
func _greedy_merge_boxes(voxel_set: Dictionary) -> Array:
    var consumed: Dictionary = {}
    var boxes: Array = []

    # Stable iteration order so the merger is deterministic.
    var keys: Array = voxel_set.keys()
    keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
        if a.y != b.y: return a.y < b.y
        if a.z != b.z: return a.z < b.z
        return a.x < b.x)

    for start: Vector3i in keys:
        if consumed.has(start):
            continue

        # Grow in +X.
        var sx := 1
        while voxel_set.has(start + Vector3i(sx, 0, 0)) \
                and not consumed.has(start + Vector3i(sx, 0, 0)):
            sx += 1

        # Grow in +Z, requiring the full X-strip to be available at each step.
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

        # Grow in +Y, requiring the full X*Z slab to be available at each step.
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

        # Mark every voxel in this box as consumed.
        for dx in range(sx):
            for dy in range(sy):
                for dz in range(sz):
                    consumed[start + Vector3i(dx, dy, dz)] = true

        boxes.append({
            "min":  start,
            "size": Vector3i(sx, sy, sz),
        })

    return boxes
