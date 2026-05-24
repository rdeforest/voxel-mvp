class_name FlattenAction
extends AdditiveAction

const GRID_ID = 0

var plane_point: Vector3   # a point the flatten plane passes through
var normal:      Vector3   # normal of the flatten plane (unit length)
var radius:      float

var terrain:     VoxelLodTerrain
var player:      CharacterBody3D

var _work: Array         = []   # [[Vector3i cell, float sdf], ...]
var _work_computed: bool = false


func _init(
    p_plane_point: Vector3,
    p_normal:      Vector3,
    p_radius:      float,
    p_terrain:     VoxelLodTerrain,
    p_player:      CharacterBody3D,
) -> void:
    plane_point = p_plane_point
    normal      = p_normal.normalized()
    radius      = p_radius
    terrain     = p_terrain
    player      = p_player


func validate() -> bool:
    _ensure_work()
    if _work.is_empty():
        return false
    if _would_endanger_player():
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
    p.refused = _work.is_empty() or _would_endanger_player()
    return p

func execute() -> void:
    if terrain == null:
        push_error("FlattenAction.execute(): no terrain")
        return

    _ensure_work()
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    for entry in _work:
        vt.set_voxel_f(entry[0], entry[1])

    var origin := plane_point - Vector3.ONE *  radius
    var dims   :=                Vector3.ONE * (radius * 2.0)
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(GRID_ID, origin, dims))


# --- Internals ---

# Refuse if any work cell would either bury the player (fill into their
# capsule) or knock their support out (remove the cell under their feet).
# Capsule defaults: radius 0.5, total height 3.0, origin at center.
func _would_endanger_player() -> bool:
    if player == null:
        return false
    var ppos := player.global_position
    var capsule_aabb := AABB(
        ppos + Vector3(-0.6, -1.5, -0.6),
        Vector3(1.2, 3.0, 1.2))
    var support_aabb := AABB(
        ppos + Vector3(-0.6, -3.0, -0.6),
        Vector3(1.2, 1.5, 1.2))
    for entry in _work:
        var center := Vector3(entry[0]) + Vector3.ONE * 0.5
        var sdf:  float = entry[1]
        if sdf < 0.0 and capsule_aabb.has_point(center):   return true
        if sdf > 0.0 and support_aabb.has_point(center):   return true
    return false

func _ensure_work() -> void:
    if _work_computed or terrain == null:
        return
    _work          = _compute_work()
    _work_computed = true

# Bucket cells by column (lateral position on the plane). For each column,
# only emit work on a side when both phases (air + solid) are present on
# that side — i.e. the cut actually reaches an existing surface within
# radius. Skip columns whose +N side is all-solid (would dig a buried slot)
# or whose -N side is all-air (would float).
func _compute_work() -> Array:
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF

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
            var is_solid := vt.get_voxel_f(pos) < VoxelConstants.SDF_SOLID_THRESHOLD
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
