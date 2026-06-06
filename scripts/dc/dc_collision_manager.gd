class_name DCCollisionManager
extends Node3D

# Body-driven, just-in-time terrain collision — the "single-mesher consolidation"
# touching down. Collision is needed only where a dynamic body can touch terrain, so
# we cook fine `ConcavePolygonShape3D` tiles from OUR DC mesher (crack-free, the same
# field the render uses) in the neighbourhood of each active body, and evict them when
# no body is near. godot_voxel's per-block collision is turned off (world.tscn:
# generate_collisions = false); this replaces it.
#
# Cost is trivial (a 16^3 tile cooks in ~0.004 ms — see test_spike_collision_cook),
# so cooking happens synchronously each physics tick BEFORE bodies move
# (process_priority below default). The SDF backstop (see DCCollisionManager.depenetrate,
# used by the player) is the always-correct floor for the rare frame a tile isn't
# ready yet. Re-cooks tiles an edit overlaps; gated on world_ready like the rest.

const TILE        := 16          # collision tile edge (world m); 2^DEPTH
const DIM         := TILE + 1    # corner samples
const DEPTH       := 4           # log2(TILE) — uniform full-res octree over the tile
const COOK_BUDGET := 8           # tiles cooked per physics tick (each ~0.004 ms)
const LOOKAHEAD   := 0.25        # seconds of velocity to pre-cook ahead of a body
const BODY_MARGIN := 1.5         # extra m around a body's point when gathering tiles
const DWELL       := 1.0         # seconds an unused tile lingers before eviction

var _terrain: VoxelLodTerrain
var _player:  CharacterBody3D
var _body:    StaticBody3D                 # holds every active tile's CollisionShape3D
var _reader:  DCRegionReader
var _mesher:  DCOctreeMesher
var _tiles:   Dictionary = {}              # Vector3i coord -> {shape: CollisionShape3D|null, idle: float}
var _active := false


func setup(terrain: VoxelLodTerrain, player: CharacterBody3D) -> void:
    _terrain = terrain
    _player  = player
    _reader  = DCRegionReader.new()
    _mesher  = DCOctreeMesher.new()
    _body = StaticBody3D.new()
    _body.name = "DCTerrainCollision"
    add_child(_body)
    process_priority = -10     # cook tiles before bodies move this tick
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_edit)
    VoxelEventBusSingleton.subscribe(WorldReadyEvent.CHANNEL, _on_world_ready)


func _on_world_ready(_event: VoxelEvent) -> void:
    _active = true


func _physics_process(delta: float) -> void:
    if not _active:
        return
    var t0 := Time.get_ticks_usec()
    var needed := _needed_tiles()
    var cooked := 0
    for coord in needed:
        if not _tiles.has(coord) and cooked < COOK_BUDGET:
            _cook(coord)
            cooked += 1
        if _tiles.has(coord):
            _tiles[coord].idle = 0.0
    _age_and_evict(needed, delta)
    Perf.report("DC collision (%d tiles)" % _tiles.size(), (Time.get_ticks_usec() - t0) / 1000.0)


# --- Tile selection: the union of every active body's swept neighbourhood ---

func _needed_tiles() -> Dictionary:
    var set := {}
    for body in _active_bodies():
        _add_tiles_for_aabb(_swept_aabb(body), set)
    return set

func _active_bodies() -> Array:
    var bodies: Array = []
    if is_instance_valid(_player):
        bodies.append(_player)
    for child in get_parent().get_children():
        var rb := child as RigidBody3D
        if rb != null and not rb.sleeping:
            bodies.append(rb)
    return bodies

func _swept_aabb(body: Node3D) -> AABB:
    var pos := body.global_position
    var vel := Vector3.ZERO
    if body is CharacterBody3D:
        vel = (body as CharacterBody3D).velocity
    elif body is RigidBody3D:
        vel = (body as RigidBody3D).linear_velocity
    var ahead := pos + vel * LOOKAHEAD
    var lo := pos.min(ahead) - Vector3.ONE * BODY_MARGIN
    var hi := pos.max(ahead) + Vector3.ONE * BODY_MARGIN
    return AABB(lo, hi - lo)

func _add_tiles_for_aabb(aabb: AABB, set: Dictionary) -> void:
    var lo := (aabb.position / float(TILE)).floor()
    var hi := ((aabb.position + aabb.size) / float(TILE)).floor()
    for x in range(int(lo.x), int(hi.x) + 1):
        for y in range(int(lo.y), int(hi.y) + 1):
            for z in range(int(lo.z), int(hi.z) + 1):
                set[Vector3i(x, y, z)] = true

func _age_and_evict(needed: Dictionary, delta: float) -> void:
    var evict: Array = []
    for coord in _tiles:
        if needed.has(coord):
            continue
        _tiles[coord].idle += delta
        if _tiles[coord].idle > DWELL:
            evict.append(coord)
    for coord in evict:
        _evict(coord)


# --- Cook / evict ---

func _cook(coord: Vector3i) -> void:
    var origin := coord * TILE
    var data := _reader.read_sdf_lod0(_terrain, origin, Vector3i(DIM, DIM, DIM))
    if data.size() != DIM * DIM * DIM:
        return   # region not streamed yet — try next tick; the SDF backstop covers the gap
    var arrays := _mesher.mesh_clipmap(
        [data], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        Vector3.ZERO, 1e9, DEPTH)
    var entry := {"shape": null, "idle": 0.0}
    if not arrays.is_empty():
        entry["shape"] = _build_shape(arrays, origin)
    _tiles[coord] = entry

func _build_shape(arrays: Array, origin: Vector3i) -> CollisionShape3D:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var faces := PackedVector3Array()
    faces.resize(idx.size())
    for i in idx.size():
        faces[i] = verts[idx[i]]
    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(faces)               # mesh verts are in tile-local space [0, TILE]
    var cs := CollisionShape3D.new()
    cs.shape = shape
    cs.position = Vector3(origin)         # offset the tile to its world origin
    _body.add_child(cs)
    return cs

func _evict(coord: Vector3i) -> void:
    var shape = _tiles[coord]["shape"]
    if shape != null:
        shape.queue_free()
    _tiles.erase(coord)


# --- Edits: drop cooked tiles the edit touched; they re-cook next tick if needed ---

func _on_edit(event: TerrainSdfChangedEvent) -> void:
    var aabb := AABB(event.box_origin, event.box_size).grow(1.0)
    var lo := (aabb.position / float(TILE)).floor()
    var hi := ((aabb.position + aabb.size) / float(TILE)).floor()
    for x in range(int(lo.x), int(hi.x) + 1):
        for y in range(int(lo.y), int(hi.y) + 1):
            for z in range(int(lo.z), int(hi.z) + 1):
                var coord := Vector3i(x, y, z)
                if _tiles.has(coord):
                    _evict(coord)


# --- SDF backstop (the always-correct floor; used by the player) ---

# If `pos` (a body centre with the given clearance radius) is inside solid terrain,
# return a corrected position pushed back out along the SDF gradient; else `pos`
# unchanged. Uses gradient-normalized distance (f/|∇f|) so it's correct on the
# terrain's non-unit-distance SDF (see test_spike_sdf_backstop). Cheap; safe to call
# every frame after a move.
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
