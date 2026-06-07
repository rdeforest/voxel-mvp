class_name DCCollisionManager
extends Node3D

# Body-driven terrain collision from OUR DC mesher (the single-mesher consolidation).
# Collision is needed only where a dynamic body can touch terrain, so we cook a
# COHERENT octree region around each active body (the player + awake RigidBody debris)
# — ONE mesh per region, so there are no inter-tile seams to slip through (the flaw of
# the earlier per-16³-tile version: raycasts and bodies fell through tile-boundary
# cracks). The player's region is sized to also cover its aim reach, so dig/probe/
# build raycasts always have terrain to hit. godot_voxel collision is off
# (world._enter_tree). A region recooks when its body drifts past RECOOK_DIST or an
# edit overlaps it, and is evicted when the body sleeps or leaves. Gated on world_ready.
#
# Cook is cheap (64³ region ~0.15 ms, 32³ ~0.035 ms — test_spike_collision_cook), so
# regions cook synchronously before bodies move (process_priority below default). The
# SDF backstop (depenetrate, used by the player) is the always-correct floor for the
# frame before a region is ready.

const PLAYER_REGION := 64    # edge in metres (2^DEPTH); covers the player body + ~24 m aim reach
const DEBRIS_REGION := 32
const RECOOK_DIST   := 8.0   # recook once a body drifts this far from its region centre
const DWELL         := 1.0   # seconds an idle region lingers before eviction
const COOK_BUDGET   := 2      # region (re)cooks per physics tick (player first)

var _terrain: VoxelLodTerrain
var _player:  CharacterBody3D
var _body:    StaticBody3D                 # holds every active region's CollisionShape3D
var _reader:  DCRegionReader
var _mesher:  DCOctreeMesher
var _regions: Dictionary = {}              # body -> {center: Vector3, origin: Vector3i, size: int, shape: CollisionShape3D|null, idle: float}
var _active := false


func setup(terrain: VoxelLodTerrain, player: CharacterBody3D) -> void:
    _terrain = terrain
    _player  = player
    _reader  = DCRegionReader.new()
    _mesher  = DCOctreeMesher.new()
    _body = StaticBody3D.new()
    _body.name = "DCTerrainCollision"
    add_child(_body)
    process_priority = -10     # cook regions before bodies move this tick
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_edit)
    VoxelEventBusSingleton.subscribe(WorldReadyEvent.CHANNEL, _on_world_ready)


func _on_world_ready(_event: VoxelEvent) -> void:
    _active = true


func _physics_process(delta: float) -> void:
    if not _active:
        return
    var t0 := Time.get_ticks_usec()
    var active := _active_bodies()   # player first
    var cooked := 0
    for body in active:
        var is_player: bool = body == _player
        # A debris already inside another region (usually the player's) needs no
        # region of its own — two coincident collision meshes under one body make it
        # jitter and never sleep.
        if not is_player and _covered_by_other(body):
            if _regions.has(body):
                _free_region(body)
            continue
        var size := PLAYER_REGION if is_player else DEBRIS_REGION
        var rec: Variant = _regions.get(body)
        var needs := rec == null
        if not needs:
            var center: Vector3 = rec["center"]
            needs = body.global_position.distance_to(center) > RECOOK_DIST
        if needs and cooked < COOK_BUDGET:
            _cook_region(body, size)
            cooked += 1
        if _regions.has(body):
            _regions[body]["idle"] = 0.0
    _evict_stale(active, delta)
    Perf.report("DC collision (%d regions)" % _regions.size(), (Time.get_ticks_usec() - t0) / 1000.0)


func _covered_by_other(body: Node3D) -> bool:
    var p := body.global_position
    for other in _regions:
        if other == body:
            continue
        var r: Dictionary = _regions[other]
        if AABB(Vector3(r["origin"]), Vector3.ONE * float(r["size"])).has_point(p):
            return true
    return false

func _active_bodies() -> Array:
    var bodies: Array = []
    if is_instance_valid(_player):
        bodies.append(_player)              # first so the player always wins the cook budget
    for child in get_parent().get_children():
        var rb := child as RigidBody3D
        if rb != null and not rb.sleeping:
            bodies.append(rb)
    return bodies


# --- Cook / evict ---

func _cook_region(body: Node3D, size: int) -> void:
    var depth := 0
    var n := size
    while n > 1:
        n >>= 1
        depth += 1                          # depth = log2(size)
    var c := body.global_position
    var half := size >> 1
    var origin := Vector3i(floori(c.x) - half, floori(c.y) - half, floori(c.z) - half)
    var dim := size + 1
    var data := _reader.read_sdf_lod0(_terrain, origin, Vector3i(dim, dim, dim))
    if data.size() != dim * dim * dim:
        return   # region not streamed yet — try next tick; the SDF backstop covers the gap
    var arrays := _mesher.mesh_clipmap(
        [data], dim, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        Vector3.ZERO, 1e9, depth)
    var old: Variant = _regions.get(body)
    if old != null and old["shape"] != null:
        old["shape"].queue_free()
    var shape: CollisionShape3D = null
    if not arrays.is_empty():
        shape = _build_shape(arrays, origin)
    _regions[body] = {"center": Vector3(origin) + Vector3.ONE * float(half), "origin": origin, "size": size, "shape": shape, "idle": 0.0}

func _build_shape(arrays: Array, origin: Vector3i) -> CollisionShape3D:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var faces := PackedVector3Array()
    faces.resize(idx.size())
    for i in idx.size():
        faces[i] = verts[idx[i]]
    var s := ConcavePolygonShape3D.new()
    s.set_faces(faces)                       # mesh verts are in region-local space [0, size]
    var cs := CollisionShape3D.new()
    cs.shape = s
    cs.position = Vector3(origin)
    _body.add_child(cs)
    return cs

func _evict_stale(active: Array, delta: float) -> void:
    var live := {}
    for b in active:
        live[b] = true
    for body in _regions.keys():
        if live.has(body):
            continue
        if not is_instance_valid(body):
            _free_region(body)
            continue
        _regions[body]["idle"] += delta
        if _regions[body]["idle"] > DWELL:
            _free_region(body)

func _free_region(body: Variant) -> void:
    var shape = _regions[body]["shape"]
    if shape != null:
        shape.queue_free()
    _regions.erase(body)


# --- Edits: recook any region the edit touched ---

func _on_edit(event: TerrainSdfChangedEvent) -> void:
    var ebox := AABB(event.box_origin, event.box_size).grow(1.0)
    for body in _regions.keys():
        var r: Dictionary = _regions[body]
        if AABB(Vector3(r["origin"]), Vector3.ONE * float(r["size"])).intersects(ebox):
            if is_instance_valid(body):
                _cook_region(body, r["size"])
            else:
                _free_region(body)


# --- SDF backstop (the always-correct floor; used by the player) ---

# If `pos` (a body centre with the given clearance radius) is inside solid terrain,
# return a corrected position pushed back out along the SDF gradient; else `pos`
# unchanged. Gradient-normalized distance (f/|∇f|) so it's correct on the terrain's
# non-unit-distance SDF (see test_spike_sdf_backstop). Cheap; safe to call each frame.
func depenetrate(pos: Vector3, radius: float) -> Vector3:
    if not _active or not is_instance_valid(_terrain):
        return pos
    var vt := _terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    var g := _sdf_grad(vt, pos)
    var gl := g.length()
    if gl < 1e-6:
        return pos
    var dist := vt.get_voxel_f(Vector3i(roundi(pos.x), roundi(pos.y), roundi(pos.z))) / gl
    if dist >= radius:
        return pos
    return pos + (g / gl) * (radius - dist)

func _sdf_grad(vt: VoxelTool, p: Vector3) -> Vector3:
    const H := 1.0
    return Vector3(
        _sdf(vt, p + Vector3(H, 0, 0)) - _sdf(vt, p - Vector3(H, 0, 0)),
        _sdf(vt, p + Vector3(0, H, 0)) - _sdf(vt, p - Vector3(0, H, 0)),
        _sdf(vt, p + Vector3(0, 0, H)) - _sdf(vt, p - Vector3(0, 0, H))) / (2.0 * H)

func _sdf(vt: VoxelTool, p: Vector3) -> float:
    return vt.get_voxel_f(Vector3i(roundi(p.x), roundi(p.y), roundi(p.z)))
