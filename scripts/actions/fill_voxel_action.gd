class_name FillVoxelAction
extends AdditiveAction

const GRID_ID  := 0
const SDF_FILL := -1.0   # comfortably inside-solid

var cell:    Vector3i
var terrain: VoxelLodTerrain
var player:  CharacterBody3D


func _init(p_cell: Vector3i, p_terrain: VoxelLodTerrain, p_player: CharacterBody3D) -> void:
    cell    = p_cell
    terrain = p_terrain
    player  = p_player


func validate() -> bool:
    if player != null:
        var capsule := AABB(
            player.global_position + Vector3(-0.6, -1.5, -0.6),
            Vector3(1.2, 3.0, 1.2))
        if capsule.has_point(Vector3(cell) + Vector3.ONE * 0.5):
            return false
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    if vt.get_voxel_f(cell) < VoxelConstants.SDF_SOLID_THRESHOLD:
        return false   # already solid — nothing to do
    return true

func execute() -> void:
    if terrain == null:
        push_error("FillVoxelAction.execute(): no terrain")
        return
    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    vt.set_voxel_f(cell, SDF_FILL)
    VoxelEventBusSingleton.emit(
        VoxelAddedEvent.CHANNEL,
        VoxelAddedEvent.new(GRID_ID, cell, Materials.STONE))
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(GRID_ID, Vector3(cell), Vector3.ONE))

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    p.solid.append(cell)
    return p
