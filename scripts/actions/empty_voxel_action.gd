class_name EmptyVoxelAction
extends Action

# Empty a single targeted cell to air — that cell and no other (StoreWrite.one_cell), or refuse.

var cell:  Vector3i
var store: EditStore

var _work_cache: Array = []
var _work_computed := false

func _init(p_cell: Vector3i, p_ctx: ActionContext) -> void:
    cell  = p_cell
    store = p_ctx.store

func validate() -> bool:
    if store == null:
        return false
    if not TerrainProbe.is_solid(store, cell):
        return false   # already air — nothing to do
    return not _work().is_empty()   # else no corner write empties it without emptying a neighbour

func execute() -> void:
    if _work().is_empty():
        return
    var before := CellFlips.snapshot(store, StoreWrite.lattice(store, _work()).cells())
    var box    := StoreWrite.cells(store, _work(), func(_entry): return -1)
    CellFlips.since(store, before).emit(store)
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, box.position, box.size))

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    if store != null and not _work().is_empty():
        StoreWrite.lattice(store, _work()).flips(store).add_to(p)
    if p.is_empty():
        p.air.append(cell)   # nothing would change: still show (refused) what was aimed at
    return p


func _work() -> Array:
    if not _work_computed and store != null:
        _work_cache    = StoreWrite.one_cell(store, cell, false)
        _work_computed = true
    return _work_cache
