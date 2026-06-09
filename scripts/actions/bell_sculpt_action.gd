class_name BellSculptAction
extends PlayerSafeAction

# Raise and Lower are one operation with opposite sign: push a quartic "bell" of SDF
# over the brush's XZ cylinder, shifting the air/solid boundary up (raise) or down
# (lower) per column. `_sign` is -1 (raise: subtract the bell -> boundary rises) or
# +1 (lower). Refuses if the reshape would bury or drop the player — Lower used to
# skip this check entirely and could carve the ground out from under the player.

const AMPLITUDE_RATIO := 0.5   # bell peak/depth = radius * this

var position: Vector3
var radius:   float
var terrain:  VoxelLodTerrain
var _sign:    float

var _work: Array         = []   # [[Vector3i cell, float new_sdf, float old_sdf], ...]
var _work_computed: bool = false


func _init(p_position: Vector3, p_radius: float, p_terrain: VoxelLodTerrain,
        p_player: CharacterBody3D, p_sign: float) -> void:
    position = p_position
    radius   = p_radius
    terrain  = p_terrain
    player   = p_player
    _sign    = p_sign


func validate() -> bool:
    _ensure_work()
    return not _work.is_empty() and not _endangers()

func execute() -> void:
    if terrain == null:
        push_error("BellSculptAction.execute(): no terrain")
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
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, origin, dims))

func preview() -> ActionPreview:
    _ensure_work()
    var p := ActionPreview.new()
    p.refused = _work.is_empty() or _endangers()
    var t := VoxelConstants.SDF_SOLID_THRESHOLD
    for entry in _work:
        var old_sdf: float = entry[2]
        var new_sdf: float = entry[1]
        if old_sdf >= t and new_sdf < t:
            p.solid.append(entry[0])
        elif old_sdf < t and new_sdf >= t:
            p.air.append(entry[0])
    return p


# --- Internals ---

func _ensure_work() -> void:
    if _work_computed or terrain == null:
        return
    _work          = _compute_work()
    _work_computed = true

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
        var t       := d2 / r2
        var falloff := (1.0 - t) * (1.0 - t)   # quartic
        var bell    := amplitude * falloff
        var old_sdf := vt.get_voxel_f(cell)
        out.append([cell, old_sdf + _sign * bell, old_sdf])
    )
    return out

# Bury (a cell became solid in the capsule) or drop (a cell became air in the support
# box). Raise only ever makes solid, Lower only ever makes air, so each direction is a
# no-op for the other — one check serves both.
func _endangers() -> bool:
    if player == null:
        return false
    var t := VoxelConstants.SDF_SOLID_THRESHOLD
    for entry in _work:
        var old_sdf: float = entry[2]
        var new_sdf: float = entry[1]
        if old_sdf >= t and new_sdf < t and buries(entry[0]):
            return true
        if old_sdf < t and new_sdf >= t and drops(entry[0]):
            return true
    return false
