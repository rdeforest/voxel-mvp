class_name FillVoxelAction
extends AdditiveAction

# Fill a single targeted cell with solid of the current material.

var cell:    Vector3i
var store:   EditStore


func _init(p_cell: Vector3i, p_store: EditStore, p_player: CharacterBody3D, p_material: StringName = &"Stone") -> void:
    cell          = p_cell
    store         = p_store
    player        = p_player
    material_name = p_material


func validate() -> bool:
    if buries(cell):
        return false   # would fill into the player's body
    if store.sample(Vector3(cell)) < VoxelConstants.SDF_SOLID_THRESHOLD:
        return false   # already solid — nothing to do
    return true

func execute() -> void:
    if store == null:
        push_error("FillVoxelAction.execute(): no store")
        return
    StoreWrite.cells(store, [[cell, VoxelConstants.SDF_SOLID]],
        func(_entry): return MaterialPalette.index_of(material_name))
    emit_added([cell])
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, Vector3(cell), Vector3.ONE))

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    p.solid.append(cell)
    return p
