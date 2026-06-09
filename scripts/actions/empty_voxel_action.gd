class_name EmptyVoxelAction
extends Action


var cell:    Vector3i
var terrain: VoxelLodTerrain


func _init(p_cell: Vector3i, p_terrain: VoxelLodTerrain) -> void:
    cell    = p_cell
    terrain = p_terrain


func validate() -> bool:
    if terrain == null:
        return false
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    if vt.get_voxel_f(cell) >= VoxelConstants.SDF_SOLID_THRESHOLD:
        return false   # already air — nothing to do
    return true

func execute() -> void:
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    vt.set_voxel_f(cell, VoxelConstants.SDF_AIR)
    VoxelEventBusSingleton.emit(
        VoxelRemovedEvent.CHANNEL,
        VoxelRemovedEvent.new(VoxelConstants.GRID_ID, cell))
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, Vector3(cell), Vector3.ONE))

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    p.air.append(cell)
    return p
