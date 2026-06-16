class_name EmptyVoxelAction
extends Action


var cell:    Vector3i
var store:   EditStore


func _init(p_cell: Vector3i, p_ctx: ActionContext) -> void:
    cell  = p_cell
    store = p_ctx.store


func validate() -> bool:
    if store == null:
        return false
    if store.sample(Vector3(cell)) >= VoxelConstants.SDF_SOLID_THRESHOLD:
        return false   # already air — nothing to do
    return true

func execute() -> void:
    StoreWrite.cells(store, [[cell, VoxelConstants.SDF_AIR]], func(_entry): return -1)
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
