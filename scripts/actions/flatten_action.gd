class_name FlattenAction
extends PlayerSafeAction

var plane_point: Vector3   # a point the flatten plane passes through
var normal:      Vector3   # normal of the flatten plane (unit length)
var radius:      float

var store:       EditStore

var _work: Array[LatticeEdit] = []   # the lattice points written (material kept)
var _lattice: SdfLattice = null      # the field _work writes (player safety)
var _flips: CellFlips    = CellFlips.new()   # what that does to cells (the ghost)
var _work_computed: bool = false


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


func validate() -> bool:
    _ensure_work()
    if _work.is_empty():
        return false
    if endangered_by(_lattice, store):
        return false
    return true

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    _ensure_work()
    _flips.add_to(p)
    p.refused = _work.is_empty() or endangered_by(_lattice, store)
    return p

func execute() -> void:
    if store == null:
        push_error("FlattenAction.execute(): no store")
        return

    _ensure_work()
    var box := StoreWrite.cells(store, _work)   # keep each leaf's current material
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, box.position, box.size))


# --- Internals ---

func _ensure_work() -> void:
    if _work_computed or store == null:
        return
    _work          = _compute_work()
    _lattice       = StoreWrite.lattice(store, _work) if not _work.is_empty() else null
    _flips         = _lattice.flips(store) if _lattice != null else CellFlips.new()
    _work_computed = true

# Works on store LATTICE points (StoreWrite writes corners), reading and writing the field at
# the same point; which CELLS that flips is _flips.
# Bucket points by column (lateral position on the plane). For each column,
# only emit work on a side when both phases (air + solid) are present on
# that side — i.e. the cut actually reaches an existing surface within
# radius. Skip columns whose +N side is all-solid (would dig a buried slot)
# or whose -N side is all-air (would float).
func _compute_work() -> Array[LatticeEdit]:
    var origin := plane_point - Vector3.ONE *  radius
    var dims   :=                Vector3.ONE * (radius * 2.0)
    var columns: Dictionary = {}   # lateral key -> _Column

    VoxelUtils.for_each_in_bounding_box(
        origin,
        dims,
        func(pos: Vector3i) -> void:
            var plane_dist: float = normal.dot(Vector3(pos) - plane_point)
            if absf(plane_dist) > radius:
                return
            var lateral := Vector3(pos) - normal * plane_dist
            var key     := Vector3i(roundi(lateral.x), roundi(lateral.y), roundi(lateral.z))
            if not columns.has(key):
                columns[key] = _Column.new()
            columns[key].add(pos, plane_dist, store.sample(Vector3(pos)) < VoxelConstants.SDF_SOLID_THRESHOLD)
    )

    var work: Array[LatticeEdit] = []
    for column: _Column in columns.values():
        for c: _Candidate in column.candidates:
            if c.edit.sdf > 0.0 and column.pos_has_air and c.was_solid:
                work.append(c.edit)
            elif c.edit.sdf < 0.0 and column.neg_has_solid and not c.was_solid:
                work.append(c.edit)
    return work


# One lateral column of lattice points across the plane. Each point's candidate edit writes its
# signed distance to the plane, paired with whether the store holds solid there now; the two
# flags say whether the cut reaches an existing surface on each side.
class _Column:
    var candidates: Array[_Candidate] = []
    var pos_has_air   := false
    var neg_has_solid := false

    func add(point: Vector3i, plane_dist: float, is_solid: bool) -> void:
        candidates.append(_Candidate.new(LatticeEdit.new(point, plane_dist), is_solid))
        pos_has_air   = pos_has_air   or (plane_dist > 0.0 and not is_solid)
        neg_has_solid = neg_has_solid or (plane_dist < 0.0 and is_solid)


class _Candidate:
    var edit:      LatticeEdit
    var was_solid: bool

    func _init(p_edit: LatticeEdit, p_was_solid: bool) -> void:
        edit      = p_edit
        was_solid = p_was_solid
