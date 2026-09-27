class_name SetMaterialAction
extends PlayerSafeAction

# Instrument (doc 22, the instrument layer): one cell's material set, written through StoreWrite
# like any edit. The cell is the leaf whose origin is `cell` (the one TerrainProbe.material reads).
#
# Only an edited leaf holds a material, so a cell the generator held is stored first: the write
# rewrites the 2x2x2 leaves around lattice point `cell` from the field as it stands, every lattice
# point keeping its value. Between lattice points a stored leaf is a trilerp of its corners, not the
# generator, so a cell's sample point can move and even flip; the event carries whatever flipped.
# No player-safety refusal, as for every instrument.

var cell:          Vector3i
var material_name: StringName
var store:         EditStore

var _lattice: SdfLattice = null


func _init(p_cell: Vector3i, p_material: StringName, p_ctx: ActionContext) -> void:
    cell          = p_cell
    material_name = p_material
    store         = p_ctx.store
    player        = p_ctx.player
    source        = p_ctx.source


func to_step() -> Dictionary:
    return {"cell": StepFields.encode_cell(cell), "material": material_name}

static func from_step(f: StepFields, ctx: ActionContext) -> Action:
    return SetMaterialAction.new(f.cell("cell"), f.material("material"), ctx)


# Why the write won't run; "" when it will.
func refusal() -> String:
    if store == null:
        return "no store"
    if not MaterialPalette.NAMES.has(material_name):
        return "\"%s\" is not a material" % material_name
    if TerrainProbe.material(store, cell) == MaterialPalette.index_of(material_name):
        return "cell %s is already %s" % [cell, material_name]
    return ""


func validate() -> bool:
    return refusal() == ""


func execute() -> void:
    var lat := written_field()
    TerrainSdfChangedEvent.announce(source, lat.region(), StoreWrite.write(store, lat, _work()))


# The cells the write would flip, or the cell itself when it flips none or is refused.
func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    if not p.refused:
        written_field().flips(store).add_to(p)
    if p.is_empty():
        p.solid.append(cell)
    return p


# The field execute() writes, built against the store before it runs.
func written_field() -> SdfLattice:
    if _lattice == null:
        _lattice = StoreWrite.lattice(store, _work())
    return _lattice


# Lattice point `cell` at the value the lattice reads for it anyway (its owner leaf, the target
# cell: the point's upper side), so only the material is new.
func _work() -> Array[LatticeEdit]:
    var point := Vector3(cell)
    var held  := store.sample_toward(point, VoxelUtils.sample_point(cell))
    var work: Array[LatticeEdit] = [LatticeEdit.new(cell, held, MaterialPalette.index_of(material_name))]
    return work
