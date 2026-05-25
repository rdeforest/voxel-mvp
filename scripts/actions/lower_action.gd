class_name LowerAction
extends Action

const GRID_ID         := 0
const AMPLITUDE_RATIO := 0.5   # bell depth = radius * this

var position: Vector3
var radius:   float
var terrain:  VoxelLodTerrain

var _work:          Array = []   # [[Vector3i cell, float new_sdf, float old_sdf], ...]
var _work_computed: bool  = false


func _init(p_position: Vector3, p_radius: float, p_terrain: VoxelLodTerrain) -> void:
    position = p_position
    radius   = p_radius
    terrain  = p_terrain


func validate() -> bool:
    _ensure_work()
    return not _work.is_empty()

func execute() -> void:
    if terrain == null:
        push_error("LowerAction.execute(): no terrain")
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
    p.refused = _work.is_empty()
    for entry in _work:
        var old_sdf: float = entry[2]
        var new_sdf: float = entry[1]
        if old_sdf <  VoxelConstants.SDF_SOLID_THRESHOLD \
                and new_sdf >= VoxelConstants.SDF_SOLID_THRESHOLD:
            p.air.append(entry[0])
    return p


# --- Internals ---

func _ensure_work() -> void:
    if _work_computed or terrain == null:
        return
    _work          = _compute_work()
    _work_computed = true

# Mirror of RaiseAction: add the bell height to SDF, shifting the
# air-solid boundary downward by that amount in each column of the
# brush's XZ cylinder.
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
        var falloff := (1.0 - t) * (1.0 - t)
        var bell    := amplitude * falloff
        var old_sdf := vt.get_voxel_f(cell)
        out.append([cell, old_sdf + bell, old_sdf])
    )
    return out
