class_name FlattenAction
extends PlayerSafeAction

var plane_point: Vector3   # a point the flatten plane passes through
var normal:      Vector3   # normal of the flatten plane (unit length)
var radius:      float

var store:       EditStore

var _work: Array         = []   # [[Vector3i cell, float sdf], ...]
var _work_computed: bool = false


func _init(
    p_plane_point: Vector3,
    p_normal:      Vector3,
    p_radius:      float,
    p_store:       EditStore,
    p_player:      CharacterBody3D,
) -> void:
    plane_point = p_plane_point
    normal      = p_normal.normalized()
    radius      = p_radius
    store       = p_store
    player      = p_player


func validate() -> bool:
    _ensure_work()
    if _work.is_empty():
        return false
    if _endangers():
        return false
    return true

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    _ensure_work()
    for entry in _work:
        if entry[1] > 0.0:
            p.air.append(entry[0])
        else:
            p.solid.append(entry[0])
    p.refused = _work.is_empty() or _endangers()
    return p

func execute() -> void:
    if store == null:
        push_error("FlattenAction.execute(): no store")
        return

    _ensure_work()
    StoreWrite.cells(store, _work, func(_entry): return -1)   # keep each cell's current material

    var origin := plane_point - Vector3.ONE *  radius
    var dims   :=                Vector3.ONE * (radius * 2.0)
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, origin, dims))


# --- Internals ---

# Refuse if any work cell would bury the player (new solid in their capsule) or knock
# their support out (new air under their feet). The boxes live in PlayerSafeAction.
func _endangers() -> bool:
    for entry in _work:
        var sdf: float = entry[1]   # the new SDF for this cell
        if sdf < 0.0 and buries(entry[0]):
            return true
        if sdf > 0.0 and drops(entry[0]):
            return true
    return false

func _ensure_work() -> void:
    if _work_computed or store == null:
        return
    _work          = _compute_work()
    _work_computed = true

# Bucket cells by column (lateral position on the plane). For each column,
# only emit work on a side when both phases (air + solid) are present on
# that side — i.e. the cut actually reaches an existing surface within
# radius. Skip columns whose +N side is all-solid (would dig a buried slot)
# or whose -N side is all-air (would float).
func _compute_work() -> Array:
    var origin := plane_point - Vector3.ONE *  radius
    var dims   :=                Vector3.ONE * (radius * 2.0)
    var columns: Dictionary = {}

    VoxelUtils.for_each_in_bounding_box(
        origin,
        dims,
        func(pos: Vector3i) -> void:
            var plane_dist: float = normal.dot(Vector3(pos) - plane_point)
            if absf(plane_dist) > radius:
                return
            var lateral := Vector3(pos) - normal * plane_dist
            var key     := Vector3i(roundi(lateral.x), roundi(lateral.y), roundi(lateral.z))
            var is_solid := store.sample(Vector3(pos)) < VoxelConstants.SDF_SOLID_THRESHOLD
            if not columns.has(key):
                columns[key] = []
            columns[key].append([pos, plane_dist, is_solid])
    )

    var work: Array = []
    for cells in columns.values():
        var pos_has_air   := false
        var neg_has_solid := false
        for entry in cells:
            if entry[1] > 0.0 and not entry[2]:   pos_has_air   = true
            if entry[1] < 0.0 and     entry[2]:   neg_has_solid = true

        for entry in cells:
            var plane_dist: float = entry[1]
            var is_solid:   bool  = entry[2]
            if plane_dist > 0.0 and pos_has_air   and is_solid:
                work.append([entry[0], plane_dist])
            elif plane_dist < 0.0 and neg_has_solid and not is_solid:
                work.append([entry[0], plane_dist])

    return work
