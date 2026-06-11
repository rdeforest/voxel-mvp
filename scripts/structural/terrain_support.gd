class_name TerrainSupport
extends RefCounted


var voxel_data:           Dictionary[Vector3i, VoxelRecord] = {}
var dirty_queue:          Array[Vector3i]                   = []
var _lowest_registered_y: Dictionary                        = {}

# Cells whose support has settled at/below FALL_THRESHOLD — genuinely unsupported, the thaw
# trigger for the MPM substrate. Drained by the facade via take_fall_candidates() (which also
# drops them from voxel_data, since they're becoming MPM particles, not static terrain).
var fall_candidates:      Array[Vector3i]                   = []
var _fall_set:            Dictionary                        = {}

var store:                EditStore   # SDF source (generator + edits); injected by StructuralIntegrity


func _init() -> void:
    VoxelEventBusSingleton.subscribe(VoxelAddedEvent.CHANNEL,        _on_voxel_added)
    VoxelEventBusSingleton.subscribe(VoxelRemovedEvent.CHANNEL,      _on_voxel_removed)
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_terrain_sdf_changed)


# --- Bus handlers ---

func _on_voxel_added(event: VoxelAddedEvent) -> void:
    _register_voxel(event.pos, event.material)

func _on_voxel_removed(event: VoxelRemovedEvent) -> void:
    _remove_voxel(event.pos)

func _on_terrain_sdf_changed(event: TerrainSdfChangedEvent) -> void:
    if store == null:
        return
    for cell in event.cells:
        var is_solid := store.sample(Vector3(cell)) < VoxelConstants.SDF_SOLID_THRESHOLD
        if voxel_data.has(cell):
            # Tracked record exists. If the SDF has become air (e.g. via
            # LowerAction or any other path that didn't explicitly emit
            # voxel_removed for this cell), drop the record now so we
            # don't end up with phantoms — tracked cells whose surface
            # no longer exists.
            if not is_solid:
                _remove_voxel(cell)
                VoxelEventBusSingleton.emit(
                    VoxelRemovedEvent.CHANNEL,
                    VoxelRemovedEvent.new(VoxelConstants.GRID_ID, cell))
                continue
            if not voxel_data[cell].dirty:
                voxel_data[cell].dirty = true
                dirty_queue.append(cell)
            continue
        # Untracked cell. Register if it's a newly-exposed boundary
        # (solid with at least one air neighbour).
        if not is_solid:
            continue
        for neighbor in VoxelUtils.neighbors(cell):
            if store.sample(Vector3(neighbor)) >= VoxelConstants.SDF_SOLID_THRESHOLD:
                _register_voxel(cell, Materials.STONE)
                break


# --- Internal data ops (also called by snapshot restore) ---

func _register_voxel(pos: Vector3i, material: Materials) -> void:
    voxel_data[pos] = VoxelRecord.new(material)
    dirty_queue.append(pos)
    _track_column_low(pos)

# Restore a voxel from a saved snapshot: bypasses propagation by trusting the
# saved support, which was captured while the world was quiescent.
func restore_voxel(pos: Vector3i, material: Materials, support: float) -> void:
    var rec := VoxelRecord.new(material)
    rec.support = support
    rec.dirty   = false
    voxel_data[pos] = rec
    _track_column_low(pos)

func _remove_voxel(pos: Vector3i) -> void:
    voxel_data.erase(pos)
    var col := Vector2i(pos.x, pos.z)
    if _lowest_registered_y.has(col) and _lowest_registered_y[col] == pos.y:
        _recompute_column_low(col)
    dirty_neighbors_of(pos)

func _track_column_low(pos: Vector3i) -> void:
    var col := Vector2i(pos.x, pos.z)
    if not _lowest_registered_y.has(col) or _lowest_registered_y[col] > pos.y:
        _lowest_registered_y[col] = pos.y

func dirty_neighbors_of(cell: Vector3i) -> void:
    for neighbor in VoxelUtils.neighbors(cell):
        if voxel_data.has(neighbor) and not voxel_data[neighbor].dirty:
            voxel_data[neighbor].dirty = true
            dirty_queue.append(neighbor)


# --- Queries ---

func get_support(pos: Vector3i) -> float:
    if voxel_data.has(pos):
        return voxel_data[pos].support
    return VoxelConstants.FULL_SUPPORT

func is_natural_terrain(pos: Vector3i) -> bool:
    if voxel_data.has(pos):
        return false
    if not _is_terrain_solid(pos):
        return false
    return _is_bedrock(pos)


# --- Propagation ---

func process_dirty_queue() -> void:
    var processed := 0
    while not dirty_queue.is_empty() and processed < VoxelConstants.PROPAGATION_BUDGET:
        var pos: Vector3i = dirty_queue.pop_front()

        if not voxel_data.has(pos):
            continue
        if not voxel_data[pos].dirty:
            continue

        var old_support: float = voxel_data[pos].support
        var new_support := _calculate_support(pos)
        voxel_data[pos].support = new_support
        voxel_data[pos].dirty   = false

        if absf(new_support - old_support) > VoxelConstants.SUPPORT_EPSILON:
            dirty_neighbors_of(pos)   # propagate the change through the support fixpoint

        if new_support <= VoxelConstants.FALL_THRESHOLD and not _fall_set.has(pos):
            _fall_set[pos] = true     # genuinely unsupported — a thaw candidate for MPM
            fall_candidates.append(pos)

        processed += 1


# Drain the unsupported cells (the MPM thaw trigger) and drop them from the tracked set — they're
# becoming MPM particles, no longer static terrain. Returns only cells still tracked + solid.
func take_fall_candidates() -> Array[Vector3i]:
    var out: Array[Vector3i] = []
    for pos in fall_candidates:
        if voxel_data.has(pos):
            out.append(pos)
            _remove_voxel(pos)
    fall_candidates.clear()
    _fall_set.clear()
    return out

func _calculate_support(pos: Vector3i) -> float:
    if is_natural_terrain(pos + Vector3i(0, -1, 0)):
        return VoxelConstants.FULL_SUPPORT

    var current_support := voxel_data[pos].support as float
    var best            := VoxelConstants.NO_SUPPORT
    for neighbor in VoxelUtils.neighbors(pos):
        best = maxf(best, _support_from_neighbor(neighbor, pos, current_support))

    return maxf(VoxelConstants.NO_SUPPORT, best - voxel_data[pos].material.decay)


# Classification cascade, priority order:
#   tracked voxel  → its support
#   solid above    → skip (gravity flows down)
#   solid bedrock  → VoxelConstants.FULL_SUPPORT
#   suspended mass → lazy-register, then skip
#   air            → skip
func _support_from_neighbor(neighbor: Vector3i, self_pos: Vector3i, self_support: float) -> float:
    if voxel_data.has(neighbor):
        return voxel_data[neighbor].support
    if not _is_terrain_solid(neighbor):
        return VoxelConstants.NO_SUPPORT
    if neighbor.y > self_pos.y:
        return VoxelConstants.NO_SUPPORT
    if _is_bedrock(neighbor):
        return VoxelConstants.FULL_SUPPORT
    if self_support > VoxelConstants.FALL_THRESHOLD:
        _register_voxel(neighbor, Materials.STONE)
    return VoxelConstants.NO_SUPPORT


# --- Internals ---

func _recompute_column_low(col: Vector2i) -> void:
    _lowest_registered_y.erase(col)
    for p: Vector3i in voxel_data:
        if p.x == col.x and p.z == col.y:
            if not _lowest_registered_y.has(col) or _lowest_registered_y[col] > p.y:
                _lowest_registered_y[col] = p.y

func _is_bedrock(pos: Vector3i) -> bool:
    var col := Vector2i(pos.x, pos.z)
    return not _lowest_registered_y.has(col) or _lowest_registered_y[col] > pos.y

func _is_terrain_solid(pos: Vector3i) -> bool:
    if store == null:
        return false
    return store.sample(Vector3(pos)) < VoxelConstants.SDF_SOLID_THRESHOLD
