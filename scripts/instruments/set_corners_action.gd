class_name SetCornersAction
extends PlayerSafeAction

# Instrument (doc 22, the instrument layer): one cell's 8 lattice corners set to exact values,
# written through StoreWrite like any edit, so it renders and emits its matter-changed event.
# It bypasses player safety; InstrumentCommands rescues the player (danger_of on written_field()).
#
# Corner k is the lattice point cell + CubeGeometry.corner(k): x is bit 0, y bit 1, z bit 2. The
# store holds float32 corners, so each value lands rounded to float32. Every leaf keeps its
# material. The write rewrites the 3x3x3 leaves around the cell (StoreWrite's margin), so a leaf
# the generator held becomes a stored trilerp of its corners: lattice points keep their values,
# points between them can move, which is what every StoreWrite edit does.

const CORNERS := 8

var cell:    Vector3i
var corners: PackedFloat64Array
var store:   EditStore

var _lattice: SdfLattice = null


func _init(p_cell: Vector3i, p_corners: PackedFloat64Array, p_ctx: ActionContext) -> void:
    cell    = p_cell
    corners = p_corners
    store   = p_ctx.store
    player  = p_ctx.player
    source  = p_ctx.source


func to_step() -> Dictionary:
    return {"cell": StepFields.encode_cell(cell), "corners": StepFields.encode_floats(corners)}

static func from_step(f: StepFields, ctx: ActionContext) -> Action:
    var at     := f.cell("cell")
    var values := f.floats("corners")
    if values.size() != CORNERS and f.error == "":
        f.fail("corners: expected %d values, got %d" % [CORNERS, values.size()])
    return SetCornersAction.new(at, values, ctx)


# Why the write won't run; "" when it will.
func refusal() -> String:
    if store == null:
        return "no store"
    if corners.size() != CORNERS:
        return "a cell has %d corners, not %d" % [CORNERS, corners.size()]
    for v in corners:
        if not is_finite(v):
            return "corner values must be finite numbers"
    if not written_field().writes:
        return "the corners already hold those values"
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


func _work() -> Array[LatticeEdit]:
    var work: Array[LatticeEdit] = []
    for k in CORNERS:
        work.append(LatticeEdit.new(cell + Vector3i(CubeGeometry.corner(k)), corners[k]))
    return work
