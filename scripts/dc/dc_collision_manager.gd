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
# The SDF source is the EditStore (generator + edits) — no godot_voxel read, so collision
# is always available (no streaming wait). Each region keeps a persistent scrolling buffer:
# a recook re-samples only the shell that scrolled in (movement) plus any edited box, via
# EditStore.fill_region — cheap and field-agnostic (no heightfield assumption). The mesh
# step runs over the whole region but is itself cheap (~0.15 ms — test_spike_collision_cook).
# The SDF backstop (depenetrate, used by the player) is the always-correct floor.

# Collision is a small sub-metre FOOT PATCH around each body now that AIM is a separate SDF
# raymarch (TerrainRaymarch) — the cook no longer has to span the aim reach, just the body. Cook
# cost scales with cell COUNT, so a small region is cheap at any cell size; COLLISION_CELL is
# coarser than the 0.25 render (walking doesn't need 0.25, and the SDF backstop covers anything
# finer) to keep the patch large in world terms while the cook stays a couple ms.
const COLLISION_CELL := 0.5  # world metres per collision cell (sub-metre; tunable vs render's 0.25)
const PLAYER_REGION := 16    # cells per axis (2^DEPTH) → 16 * 0.5 = 8 m foot patch around the body
const DEBRIS_REGION := 16
const RECOOK_DIST   := 3.0   # recook once a body drifts this far (m) from its region centre
const DWELL         := 1.0   # seconds an idle region lingers before eviction
const COOK_BUDGET   := 2      # region (re)cooks per physics tick (player first)

var _edit_store: EditStore                 # SDF source (generator + edits); replaces the godot_voxel read
var _player:  CharacterBody3D
var _body:    StaticBody3D                 # holds every active region's CollisionShape3D
var _mesher:  DCOctreeMesher
var _regions: Dictionary = {}              # body -> {center, origin: Vector3i, size, shape, idle, buffer: PackedFloat32Array}
var _active := false


func setup(edit_store: EditStore, player: CharacterBody3D) -> void:
    _edit_store = edit_store
    _player  = player
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
        if AABB(Vector3(r["origin"]) * COLLISION_CELL, Vector3.ONE * float(r["size"]) * COLLISION_CELL).has_point(p):
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

# `dirty` (origin/size, world cells; zero = none) forces re-sampling of an edited box —
# passed on an edit recook so the change shows even where the region didn't move.
func _cook_region(body: Node3D, size: int, dirty_origin := Vector3i.ZERO, dirty_size := Vector3i.ZERO) -> void:
    var depth := 0
    var n := size
    while n > 1:
        n >>= 1
        depth += 1                          # depth = log2(size)
    var c := body.global_position
    var half := size >> 1
    # Origin in COLLISION-CELL units (so fill_region samples on the collision grid). World = * cell.
    var origin := Vector3i(floori(c.x / COLLISION_CELL) - half, floori(c.y / COLLISION_CELL) - half, floori(c.z / COLLISION_CELL) - half)
    var dim := size + 1
    var old: Variant = _regions.get(body)
    var prev_buffer: PackedFloat32Array = old["buffer"] if old != null else PackedFloat32Array()
    var prev_origin: Vector3i = old["origin"] if old != null else Vector3i.ZERO
    # Scrolling buffer: reuse the overlap, re-sample only the shell that moved + the dirty box.
    var data := _edit_store.fill_region(origin, dim, COLLISION_CELL, prev_buffer, prev_origin, dirty_origin, dirty_size)
    # The mesher meshes the integer lattice (cell 1.0); _build_shape scales the verts to world.
    var arrays := _mesher.mesh_clipmap(
        [data], dim, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        Vector3.ZERO, 1e9, depth)
    if old != null and old["shape"] != null:
        old["shape"].queue_free()
    var shape: CollisionShape3D = null
    if not arrays.is_empty():
        shape = _build_shape(arrays, origin)
    _regions[body] = {"center": (Vector3(origin) + Vector3.ONE * float(half)) * COLLISION_CELL, "origin": origin, "size": size, "shape": shape, "idle": 0.0, "buffer": data}

func _build_shape(arrays: Array, origin: Vector3i) -> CollisionShape3D:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var faces := PackedVector3Array()
    faces.resize(idx.size())
    for i in idx.size():
        faces[i] = verts[idx[i]] * COLLISION_CELL    # lattice [0, size] -> world metres
    var s := ConcavePolygonShape3D.new()
    s.set_faces(faces)
    var cs := CollisionShape3D.new()
    cs.shape = s
    cs.position = Vector3(origin) * COLLISION_CELL    # cell-origin -> world
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
    # Dirty box in COLLISION-CELL units (the fill_region scrolling-buffer re-sample window).
    var d_o := Vector3i((ebox.position / COLLISION_CELL).floor())
    var d_s := Vector3i((ebox.size / COLLISION_CELL).ceil()) + Vector3i.ONE
    for body in _regions.keys():
        var r: Dictionary = _regions[body]
        if AABB(Vector3(r["origin"]) * COLLISION_CELL, Vector3.ONE * float(r["size"]) * COLLISION_CELL).intersects(ebox):
            if is_instance_valid(body):
                _cook_region(body, r["size"], d_o, d_s)
            else:
                _free_region(body)


# --- SDF backstop (the always-correct floor; used by the player) ---

# If `pos` (a body centre with the given clearance radius) is inside solid terrain,
# return a corrected position pushed back out along the SDF gradient; else `pos`
# unchanged. Gradient-normalized distance (f/|∇f|) so it's correct on the terrain's
# non-unit-distance SDF (see test_spike_sdf_backstop). Cheap; safe to call each frame.
func depenetrate(pos: Vector3, radius: float) -> Vector3:
    if not _active or _edit_store == null:
        return pos
    var g := _sdf_grad(pos)
    var gl := g.length()
    if gl < 1e-6:
        return pos
    var dist := _edit_store.sample(pos) / gl
    if dist >= radius:
        return pos
    return pos + (g / gl) * (radius - dist)

func _sdf_grad(p: Vector3) -> Vector3:
    const H := 1.0
    return Vector3(
        _edit_store.sample(p + Vector3(H, 0, 0)) - _edit_store.sample(p - Vector3(H, 0, 0)),
        _edit_store.sample(p + Vector3(0, H, 0)) - _edit_store.sample(p - Vector3(0, H, 0)),
        _edit_store.sample(p + Vector3(0, 0, H)) - _edit_store.sample(p - Vector3(0, 0, H))) / (2.0 * H)
