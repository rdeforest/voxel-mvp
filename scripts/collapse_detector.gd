class_name CollapseDetector
extends RefCounted

const GRID_ID = 0

var _pending_floods:    Array[PendingFlood]                       = []
var _pending_collapses: Array[PendingCollapse]                    = []
var _voxel_to_pending:  Dictionary[Vector3i, PendingCollapse]     = {}
var _claimed:           Dictionary                                = {}

var _terrain_support:   TerrainSupport
var _facade:            Node


func _init(terrain_support: TerrainSupport, facade: Node) -> void:
    _terrain_support = terrain_support
    _facade          = facade
    VoxelEventBus.subscribe(VoxelSupportChangedEvent.CHANNEL, _on_voxel_support_changed)


# --- Phases (called by StructuralIntegrity once dirty_queue settles) ---

func step() -> void:
    if not _resume_unfinished_floods(): return
    if not _scan_for_new_collapses():   return
    _reset_claims_to_pending()

func _resume_unfinished_floods() -> bool:
    while not _pending_floods.is_empty():
        var flood: PendingFlood = _pending_floods[0]
        if not _advance_flood(flood, VoxelConstants.DETECTION_BUDGET):
            return false
        _pending_floods.pop_front()
        if not flood.voxels.is_empty():
            _begin_pending_collapse(flood.voxels)
    return true

func _scan_for_new_collapses() -> bool:
    for pos in _terrain_support.voxel_data.keys():
        if _claimed.has(pos):
            continue
        if not _can_seed_collapse(pos):
            continue

        var flood := PendingFlood.new(pos)
        _claimed[pos] = true

        if not _advance_flood(flood, VoxelConstants.DETECTION_BUDGET):
            _pending_floods.append(flood)
            return false

        if not flood.voxels.is_empty():
            _begin_pending_collapse(flood.voxels)
    return true


# --- Per-frame strain accumulation ---

func tick_pending(delta: float) -> void:
    if _pending_collapses.is_empty():
        return

    for i in range(_pending_collapses.size() - 1, -1, -1):
        var pc: PendingCollapse = _pending_collapses[i]

        if not _component_still_falling(pc):
            _cancel_pending_collapse(i)
            continue

        pc.strained += delta
        if pc.strained >= VoxelConstants.STRAIN_DURATION_SEC:
            _materialize_pending_collapse(i)

func get_straining_voxels() -> Dictionary:
    return _voxel_to_pending

func is_idle() -> bool:
    return _pending_floods.is_empty() and _pending_collapses.is_empty()


# --- Bus handler: rewind strain when support comes back ---

func _on_voxel_support_changed(event: VoxelSupportChangedEvent) -> void:
    if event.new_support <= event.old_support:
        return
    if not _voxel_to_pending.has(event.pos):
        return

    var pc: PendingCollapse = _voxel_to_pending[event.pos]
    var reset_floor := VoxelConstants.STRAIN_DURATION_SEC \
        - VoxelConstants.STRAIN_RESET_SEC
    pc.strained = minf(pc.strained, reset_floor)


# --- Pending-collapse lifecycle ---

func _begin_pending_collapse(voxels: Array[Vector3i]) -> void:
    var pc := PendingCollapse.new(voxels)
    _pending_collapses.append(pc)
    for v in voxels:
        _voxel_to_pending[v] = pc
        _claimed[v] = true

func _cancel_pending_collapse(index: int) -> void:
    var pc: PendingCollapse = _pending_collapses[index]
    for v in pc.voxels:
        _voxel_to_pending.erase(v)
        _claimed.erase(v)
        _redirty_neighbors(v)
    _pending_collapses.remove_at(index)

func _materialize_pending_collapse(index: int) -> void:
    var pc: PendingCollapse = _pending_collapses[index]
    for v in pc.voxels:
        _voxel_to_pending.erase(v)
        _claimed.erase(v)
    _pending_collapses.remove_at(index)
    _materialize_collapse(pc.voxels)

func _component_still_falling(pc: PendingCollapse) -> bool:
    for v in pc.voxels:
        # A voxel removed from the world (e.g. dug out) is no longer this
        # component's problem, but the rest may still be falling — skip, don't bail.
        if not _terrain_support.voxel_data.has(v):
            continue
        if _is_fall_candidate(v):
            return true
    return false

func _redirty_neighbors(pos: Vector3i) -> void:
    _terrain_support.dirty_neighbors_of(pos)

func _reset_claims_to_pending() -> void:
    _claimed.clear()
    for pc in _pending_collapses:
        for v in pc.voxels:
            _claimed[v] = true


# --- Flood fill ---

func _advance_flood(flood: PendingFlood, budget: int) -> bool:
    var voxels:   Array[Vector3i] = flood.voxels
    var frontier: Array[Vector3i] = flood.frontier
    var visited:  Dictionary      = flood.visited

    var processed := 0
    while not frontier.is_empty() and processed < budget:
        var pos: Vector3i = frontier.pop_back()
        voxels.append(pos)
        _claimed[pos] = true
        processed += 1

        for neighbor in VoxelUtils.neighbors(pos):
            if visited.has(neighbor):
                continue
            if not _terrain_support.voxel_data.has(neighbor):
                continue
            if not _is_fall_candidate(neighbor):
                continue
            visited[neighbor] = true
            frontier.append(neighbor)

    return frontier.is_empty()

# Strict: requires support has settled. Used only to SEED a flood.
func _can_seed_collapse(pos: Vector3i) -> bool:
    if not _terrain_support.voxel_data.has(pos):
        return false
    var data: VoxelRecord = _terrain_support.voxel_data[pos]
    if data.dirty:
        return false
    return data.support <= VoxelConstants.FALL_THRESHOLD

# Permissive: a dirty voxel at/below threshold still belongs to the component.
# See docs/architecture.md → "Seed-conservative, expand-permissive".
func _is_fall_candidate(pos: Vector3i) -> bool:
    if not _terrain_support.voxel_data.has(pos):
        return false
    return _terrain_support.voxel_data[pos].support <= VoxelConstants.FALL_THRESHOLD


# --- Materialization ---

func _materialize_collapse(voxels: Array[Vector3i]) -> void:
    var body := FallingBodyFactory.from_voxels(voxels)
    _facade.get_parent().add_child(body)

    VoxelEventBus.emit(
        RegionCollapsingEvent.CHANNEL,
        RegionCollapsingEvent.new(GRID_ID, voxels))

    var voxel_tool: VoxelTool = _terrain_support.terrain.get_voxel_tool()
    voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
    voxel_tool.mode    = VoxelTool.MODE_REMOVE
    for v in voxels:
        voxel_tool.set_voxel_f(v, VoxelConstants.SDF_AIR)
        VoxelEventBus.emit(
            VoxelRemovedEvent.CHANNEL,
            VoxelRemovedEvent.new(GRID_ID, v))

    var box := _bounding_box(voxels)
    VoxelEventBus.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(GRID_ID, box.position, box.size))

static func _bounding_box(voxels: Array[Vector3i]) -> AABB:
    var lo := Vector3(voxels[0])
    var hi := lo + Vector3.ONE
    for v in voxels:
        lo = lo.min(Vector3(v))
        hi = hi.max(Vector3(v) + Vector3.ONE)
    return AABB(lo, hi - lo)
