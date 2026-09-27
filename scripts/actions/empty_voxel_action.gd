class_name EmptyVoxelAction
extends PlayerSafeAction

# Empty a single targeted cell to air — that cell and no other (StoreWrite.one_cell), or refuse.

var cell:  Vector3i
var store: EditStore

var _work_cache: Array[LatticeEdit] = []
var _work_computed := false

func _init(p_cell: Vector3i, p_ctx: ActionContext) -> void:
    cell   = p_cell
    store  = p_ctx.store
    player = p_ctx.player
    source = p_ctx.source


func to_step() -> Dictionary:
    return {"cell": StepFields.encode_cell(cell)}

static func from_step(f: StepFields, ctx: ActionContext) -> Action:
    return EmptyVoxelAction.new(f.cell("cell"), ctx)


func validate() -> bool:
    if store == null:
        return false
    if not TerrainProbe.is_solid(store, cell):
        return false   # already air — nothing to do
    if _work().is_empty():
        return false   # no corner write empties it without emptying a neighbour
    if endangered_by(StoreWrite.lattice(store, _work()), store):
        return false   # would carve the ground from under the player
    return true

func execute() -> void:
    if _work().is_empty():
        return
    var lat := StoreWrite.lattice(store, _work())
    TerrainSdfChangedEvent.announce(source, lat.region(), StoreWrite.write(store, lat, _work()))

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    if store != null and not _work().is_empty():
        StoreWrite.lattice(store, _work()).flips(store).add_to(p)
    if p.is_empty():
        p.air.append(cell)   # nothing would change: still show (refused) what was aimed at
    return p


func _work() -> Array[LatticeEdit]:
    if not _work_computed and store != null:
        _work_cache    = StoreWrite.one_cell(store, cell, false)
        _work_computed = true
    return _work_cache
