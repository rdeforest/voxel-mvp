class_name BellSculptAction
extends PlayerSafeAction

# Raise and Lower are one operation with opposite sign: push a quartic "bell" of SDF
# over the brush's XZ cylinder, shifting the air/solid boundary up (raise) or down
# (lower) per column. `_sign` is -1 (raise: subtract the bell -> boundary rises) or
# +1 (lower). Refuses if the reshape would bury or drop the player — Lower used to
# skip this check entirely and could carve the ground out from under the player.

const AMPLITUDE_RATIO := 0.5   # bell peak/depth = radius * this

var position: Vector3
var radius:   float
var store:    EditStore
var _sign:    float

var _lattice:  SdfLattice = null              # the field the reshape writes; null = it writes no point
var _flips:    CellFlips  = CellFlips.new()   # what that does to cells (the ghost)
var _computed: bool       = false


func _init(p_position: Vector3, p_radius: float, p_ctx: ActionContext, p_sign: float) -> void:
    position = p_position
    radius   = p_radius
    store    = p_ctx.store
    player   = p_ctx.player
    source   = p_ctx.source
    _sign    = p_sign


func validate() -> bool:
    _ensure_lattice()
    return _lattice != null and not endangered_by(_lattice, store)

func execute() -> void:
    if store == null:
        push_error("BellSculptAction.execute(): no store")
        return
    _ensure_lattice()
    if _lattice == null:
        return

    # A refused write (off-grid lattice) or one that moved no sample changed no matter to announce.
    var flips := StoreWrite.reshape(store, _lattice)
    if flips.changed:
        TerrainSdfChangedEvent.announce(source, _lattice.region(), flips)

func preview() -> ActionPreview:
    _ensure_lattice()
    var p := ActionPreview.new()
    p.refused = _lattice == null or endangered_by(_lattice, store)
    _flips.add_to(p)
    return p


# --- Internals ---

# The bell is evaluated at the store lattice points the write sets (their corners), not half a
# cell away at cell centres; which cells that flips is _flips.
# execute() writes this whole cached cube back, not just the bell's points, so an instance is
# single-use: one that outlived another store write would revert it inside the cube. player.gd
# builds a fresh action per click.
func _ensure_lattice() -> void:
    if _computed or store == null:
        return
    _lattice  = SdfLattice.predicted(store.predict_bell(position, radius, _sign * radius * AMPLITUDE_RATIO))
    _flips    = _lattice.flips(store) if _lattice != null else CellFlips.new()
    _computed = true
