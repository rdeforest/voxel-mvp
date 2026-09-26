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

var _work: Array         = []   # [[Vector3i lattice point, float new_sdf], ...]
var _flips: CellFlips    = CellFlips.new()   # what _work does to cells (preview + safety)
var _work_computed: bool = false


func _init(p_position: Vector3, p_radius: float, p_ctx: ActionContext, p_sign: float) -> void:
    position = p_position
    radius   = p_radius
    store    = p_ctx.store
    player   = p_ctx.player
    _sign    = p_sign


func validate() -> bool:
    _ensure_work()
    return not _work.is_empty() and not endangered_by(_flips)

func execute() -> void:
    if store == null:
        push_error("BellSculptAction.execute(): no store")
        return
    _ensure_work()
    var box := StoreWrite.cells(store, _work, func(_entry): return -1)   # reshape keeps each cell's material
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, box.position, box.size))

func preview() -> ActionPreview:
    _ensure_work()
    var p := ActionPreview.new()
    p.refused = _work.is_empty() or endangered_by(_flips)
    _flips.add_to(p)
    return p


# --- Internals ---

func _ensure_work() -> void:
    if _work_computed or store == null:
        return
    _work          = _compute_work()
    _flips         = StoreWrite.lattice(store, _work).flips(store) if not _work.is_empty() else CellFlips.new()
    _work_computed = true

func _compute_work() -> Array:
    var amplitude := radius * AMPLITUDE_RATIO
    var origin    := position - Vector3.ONE * radius
    var dims      := Vector3.ONE * (radius * 2.0)
    var r2        := radius * radius
    var out: Array = []

    # Walks store lattice points (StoreWrite writes corners), so the bell is evaluated at the
    # point it writes — not half a cell away at a cell centre.
    VoxelUtils.for_each_in_bounding_box(origin, dims, func(point: Vector3i) -> void:
        var dx := float(point.x) - position.x
        var dz := float(point.z) - position.z
        var d2 := dx * dx + dz * dz
        if d2 >= r2:
            return
        var t       := d2 / r2
        var falloff := (1.0 - t) * (1.0 - t)   # quartic
        var bell    := amplitude * falloff
        out.append([point, store.sample(Vector3(point)) + _sign * bell])
    )
    return out
