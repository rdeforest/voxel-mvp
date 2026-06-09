class_name FillVoxelAction
extends AdditiveAction

# Fill a single targeted cell with solid of the current material.

var cell:    Vector3i
var terrain: VoxelLodTerrain


func _init(p_cell: Vector3i, p_terrain: VoxelLodTerrain, p_player: CharacterBody3D, p_material: StringName = &"Stone") -> void:
    cell          = p_cell
    terrain       = p_terrain
    player        = p_player
    material_name = p_material


func validate() -> bool:
    if buries(cell):
        return false   # would fill into the player's body
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
    vt.set_voxel_f(cell, VoxelConstants.SDF_SOLID)
    emit_added([cell])
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, Vector3(cell), Vector3.ONE))

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    p.solid.append(cell)
    return p
