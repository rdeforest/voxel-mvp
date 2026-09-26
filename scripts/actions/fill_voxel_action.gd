class_name FillVoxelAction
extends AdditiveAction

# Fill a single targeted cell with solid of the current material — that cell and no other
# (StoreWrite.one_cell), or refuse.

var cell:    Vector3i
var store:   EditStore

var _work_cache: Array = []
var _work_computed := false


func _init(p_cell: Vector3i, p_ctx: ActionContext, p_material: StringName = &"Stone") -> void:
    cell          = p_cell
    store         = p_ctx.store
    player        = p_ctx.player
    material_name = p_material


func validate() -> bool:
    if store == null:
        return false
    if TerrainProbe.is_solid(store, cell):
        return false   # already solid — nothing to do
    if _work().is_empty():
        return false   # no corner write flips this cell without flipping a neighbour
    if endangered_by(_lattice().flips(store)):
        return false   # would fill into the player's body
    return true

func execute() -> void:
    if store == null:
        push_error("FillVoxelAction.execute(): no store")
        return
    if _work().is_empty():
        return
    var mat    := MaterialPalette.index_of(material_name)
    var before := CellFlips.snapshot(store, _lattice().cells())
    var box    := StoreWrite.cells(store, _work(), func(entry): return mat if entry[0] == cell else -1)
    CellFlips.since(store, before).emit(store)
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, box.position, box.size))

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    if store != null and not _work().is_empty():
        _lattice().flips(store).add_to(p)
    if p.is_empty():
        p.solid.append(cell)   # nothing would change: still show (refused) what was aimed at
    return p


func _work() -> Array:
    if not _work_computed and store != null:
        _work_cache    = StoreWrite.one_cell(store, cell, true)
        _work_computed = true
    return _work_cache

func _lattice() -> SdfLattice:
    return StoreWrite.lattice(store, _work())
