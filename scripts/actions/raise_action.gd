class_name RaiseAction
extends AdditiveAction

const GRID_ID         := 0
const AMPLITUDE_RATIO := 0.5   # bell peak = radius * this

var position: Vector3
var radius:   float
var terrain:  VoxelLodTerrain
var player:   CharacterBody3D

var _work:          Array = []   # [[Vector3i cell, float new_sdf, float old_sdf], ...]
var _work_computed: bool  = false


func _init(p_position: Vector3, p_radius: float, p_terrain: VoxelLodTerrain, p_player: CharacterBody3D) -> void:
    position = p_position
    radius   = p_radius
    terrain  = p_terrain
    player   = p_player


func validate() -> bool:
    _ensure_work()
    if _work.is_empty():
        return false
    if _would_bury_player():
        return false
    return true

func execute() -> void:
    if terrain == null:
        push_error("RaiseAction.execute(): no terrain")
        return
    _ensure_work()
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    for entry in _work:
        vt.set_voxel_f(entry[0], entry[1])
    var origin := position - Vector3.ONE * radius
    var dims   := Vector3.ONE * (radius * 2.0)
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(GRID_ID, origin, dims))

func preview() -> ActionPreview:
    _ensure_work()
    var p := ActionPreview.new()
    p.refused = _work.is_empty() or _would_bury_player()
    for entry in _work:
        var old_sdf: float = entry[2]
        var new_sdf: float = entry[1]
        if old_sdf >= VoxelConstants.SDF_SOLID_THRESHOLD \
                and new_sdf <  VoxelConstants.SDF_SOLID_THRESHOLD:
            p.solid.append(entry[0])
    return p


# --- Internals ---

func _ensure_work() -> void:
    if _work_computed or terrain == null:
        return
    _work          = _compute_work()
    _work_computed = true

# Bell-shape SDF push: for each cell within the XZ cylinder of the brush,
# subtract a height (bell peak * quartic falloff) from its SDF. That shifts
# the air-solid boundary upward by the bell height in that column.
func _compute_work() -> Array:
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF

    var amplitude := radius * AMPLITUDE_RATIO
    var origin    := position - Vector3.ONE * radius
    var dims      := Vector3.ONE * (radius * 2.0)
    var r2        := radius * radius
    var out: Array = []

    VoxelUtils.for_each_in_bounding_box(origin, dims, func(cell: Vector3i) -> void:
        var dx := float(cell.x) + 0.5 - position.x
        var dz := float(cell.z) + 0.5 - position.z
        var d2 := dx * dx + dz * dz
        if d2 >= r2:
            return
        var t      := d2 / r2
        var falloff := (1.0 - t) * (1.0 - t)   # quartic
        var bell   := amplitude * falloff
        var old_sdf := vt.get_voxel_f(cell)
        out.append([cell, old_sdf - bell, old_sdf])
    )
    return out

func _would_bury_player() -> bool:
    if player == null:
        return false
    var capsule := AABB(
        player.global_position + Vector3(-0.6, -1.5, -0.6),
        Vector3(1.2, 3.0, 1.2))
    for entry in _work:
        var center := Vector3(entry[0]) + Vector3.ONE * 0.5
        var new_sdf: float = entry[1]
        if new_sdf < VoxelConstants.SDF_SOLID_THRESHOLD and capsule.has_point(center):
            return true
    return false
