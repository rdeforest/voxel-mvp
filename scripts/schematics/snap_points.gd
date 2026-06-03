class_name SnapPoints
extends RefCounted

# Snap points follow JavaScript-style prototype inheritance with copy-on-write.
#
# A placed instance inherits its snap points *live* from its prototype (the
# Part/Assembly it was stamped from) until the player edits it. The first edit
# forks the instance: the prototype's current points are copied onto the
# instance, which then evolves independently. After that the instance is itself
# a candidate prototype.
#
# "Own" points live in node metadata (local space, so they ride the part's
# transform). The presence of the metadata key — not its emptiness — is the
# fork flag: an instance that has had every inherited point removed still
# carries an empty own-array, distinct from one that merely inherits.
#
# `proto` is the prototype's local-space points (Schematic.snap_points). It is
# read at resolve time so edits to a prototype propagate to unforked children.

const META_KEY    := &"snap_points"
const PICK_RADIUS := 0.4   # how near the cursor must be to grab a point for removal


static func has_own(node: Node3D) -> bool:
    return node.has_meta(META_KEY)

static func own_local(node: Node3D) -> PackedVector3Array:
    return node.get_meta(META_KEY, PackedVector3Array())

static func set_own(node: Node3D, points: PackedVector3Array) -> void:
    node.set_meta(META_KEY, points)

# Points in effect for this instance: its own (forked) set, else the prototype's.
static func effective_local(node: Node3D, proto: Array) -> PackedVector3Array:
    if has_own(node):
        return own_local(node)
    return _packed(proto)

static func world_points(node: Node3D, proto: Array) -> PackedVector3Array:
    var out := PackedVector3Array()
    var xf  := node.global_transform
    for p in effective_local(node, proto):
        out.append(xf * p)
    return out

static func add(node: Node3D, world_point: Vector3, proto: Array) -> void:
    _fork(node, proto)
    var pts := own_local(node)
    pts.append(node.global_transform.affine_inverse() * world_point)
    set_own(node, pts)

static func remove_nearest(node: Node3D, world_point: Vector3, max_dist: float, proto: Array) -> bool:
    var idx := _nearest_index(node, world_point, max_dist, proto)
    if idx < 0:
        return false
    _fork(node, proto)
    var pts := own_local(node)
    pts.remove_at(idx)
    set_own(node, pts)
    return true

# World-space position of the point nearest world_point within max_dist, or null.
static func nearest_world(node: Node3D, world_point: Vector3, max_dist: float, proto: Array) -> Variant:
    var idx := _nearest_index(node, world_point, max_dist, proto)
    if idx < 0:
        return null
    return node.global_transform * effective_local(node, proto)[idx]


# Every placed part's snap points, in world space. registry maps each placed
# Node3D to its PartData (whose .part is the prototype).
static func all_world(registry: Dictionary) -> PackedVector3Array:
    var out := PackedVector3Array()
    for node in registry:
        var data: PartData = registry[node]
        out.append_array(world_points(node, data.part.snap_points))
    return out

# Monopolar-magnet translation: the offset that brings the closest (ghost, world)
# snap-point pair into coincidence, or ZERO when no pair is within radius. ZERO
# is also the no-op delta, so "nothing in range" and "already coincident" both
# mean don't move.
static func snap_delta(ghost: PackedVector3Array, world: PackedVector3Array, radius: float) -> Vector3:
    var best_d := radius * radius
    var best   := Vector3.ZERO
    for g in ghost:
        for w in world:
            var d := g.distance_squared_to(w)
            if d <= best_d:
                best_d = d
                best   = w - g
    return best


# Copy the inherited points onto the instance so it can diverge. No-op once forked.
static func _fork(node: Node3D, proto: Array) -> void:
    if not has_own(node):
        set_own(node, _packed(proto))

static func _nearest_index(node: Node3D, world_point: Vector3, max_dist: float, proto: Array) -> int:
    var xf     := node.global_transform
    var local  := effective_local(node, proto)
    var best   := -1
    var best_d := max_dist * max_dist
    for i in local.size():
        var d := (xf * local[i]).distance_squared_to(world_point)
        if d <= best_d:
            best_d = d
            best   = i
    return best

static func _packed(points: Array) -> PackedVector3Array:
    var out := PackedVector3Array()
    for p in points:
        out.append(p)
    return out
