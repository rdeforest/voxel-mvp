class_name FlattenAction
extends PlayerSafeAction

var plane_point: Vector3   # a point the flatten plane passes through
var normal:      Vector3   # normal of the flatten plane (unit length)
var radius:      float

var _normal_arg: Vector3   # the normal as given; normalizing a unit vector again can move an ulp

var store:       EditStore

var _lattice:  SdfLattice = null              # the field the cut writes; null = it writes no point
var _flips:    CellFlips  = CellFlips.new()   # what that does to cells (the ghost)
var _computed: bool       = false


func _init(
    p_plane_point: Vector3,
    p_normal:      Vector3,
    p_radius:      float,
    p_ctx:         ActionContext,
) -> void:
    plane_point = p_plane_point
    normal      = p_normal.normalized()
    radius      = p_radius
    store       = p_ctx.store
    player      = p_ctx.player
    source      = p_ctx.source
    _normal_arg = p_normal


func to_step() -> Dictionary:
    return {
        "plane_point": StepFields.encode_vec3(plane_point),
        "normal":      StepFields.encode_vec3(_normal_arg),
        "radius":      radius,
    }

static func from_step(f: StepFields, ctx: ActionContext) -> Action:
    return FlattenAction.new(f.vec3("plane_point"), f.vec3("normal"), f.number("radius"), ctx)


func validate() -> bool:
    _ensure_lattice()
    return _lattice != null and not endangered_by(_lattice, store)

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    _ensure_lattice()
    _flips.add_to(p)
    p.refused = _lattice == null or endangered_by(_lattice, store)
    return p

func execute() -> void:
    if store == null:
        push_error("FlattenAction.execute(): no store")
        return

    _ensure_lattice()
    if _lattice == null:
        return

    # A refused write (off-grid lattice) or one that moved no sample changed no matter to announce.
    var flips := StoreWrite.reshape(store, _lattice)
    if flips.changed:
        TerrainSdfChangedEvent.announce(source, _lattice.region(), flips)


# --- Internals ---

# The cut (EditStore.predict_flatten) works on store LATTICE points, reading and writing the field
# at the same point; which CELLS that flips is _flips. Each point within `radius` of the plane
# takes its signed distance to the plane, but only in a column (points sharing a lateral position
# on the plane) whose cut reaches an existing surface on that side: a column whose +N side is all
# solid would dig a buried slot, one whose -N side is all air would float.
# execute() writes this whole cached cube back, not just the cut's points, so an instance is
# single-use: one that outlived another store write would revert it inside the cube. player.gd
# builds a fresh action per click.
func _ensure_lattice() -> void:
    if _computed or store == null:
        return
    _lattice  = SdfLattice.predicted(store.predict_flatten(plane_point, normal, radius))
    _flips    = _lattice.flips(store) if _lattice != null else CellFlips.new()
    _computed = true
