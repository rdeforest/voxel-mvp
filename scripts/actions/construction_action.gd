class_name ConstructionAction
extends AdditiveAction

# Placing a part is a voxel imprint: stamp the part's box brush into the EditStore (SDF +
# material) via VoxelImprint — no separate Node3D, no part/terrain dichotomy. The part
# becomes terrain voxels the DC mesher draws (in the part's material colour) and the
# structural sim simulates. (docs/roadmap/design/03-dc-qef-geometry.md §"Imprinting, not CSG".)

var part:          Part
var placement_pos: Vector3    # world position for the rotated bottom-center
var rotation:      Vector3    # per-axis rotation in degrees (X, Y, Z), continuous
var store:         EditStore
# material_name (the part's material) and player are inherited from AdditiveAction.

var _cells:          Array[Vector3i] = []
var _cells_computed: bool            = false

# Cached prediction from the very field the imprint writes (VoxelImprint.lattice) — the currency
# CsgAction uses. The player-safety refusal and the attach test read the field itself; the ghost
# reads the cells it flips; execute()'s events are the same flips measured across the write. A
# part thinner than a cell can write real geometry that flips no cell centre, which is why safety
# and attachment don't go through the flips.
var _lattice:        SdfLattice      = null
var _flips:          CellFlips       = CellFlips.new()
var _flips_computed: bool            = false

# Attachment reach: a part attaches if existing solid lies at a lattice point within one lattice
# cell of the part's own geometry (the half-diagonal: every point of the part has a lattice point
# that close), or one gameplay cell below such a point — it overlaps terrain or rests on it.
const _ATTACH_DOWN := Vector3.DOWN * VoxelConstants.VOXEL_SIZE


func _init(
    p_part:     Part,
    p_pos:      Vector3,
    p_rotation: Vector3,
    p_material: StringName,
    p_ctx:      ActionContext,
) -> void:
    part          = p_part
    placement_pos = p_pos
    rotation      = p_rotation
    material_name = p_material
    store         = p_ctx.store
    player        = p_ctx.player


func validate() -> bool:
    if store == null:
        return false
    _ensure_flips()
    if endangered_by(_lattice, store):
        return false   # would bury the player
    return _attached()


func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.refused = not validate()
    if store == null:
        return p
    _ensure_flips()
    p.part.append_array(_flips.solid)   # drawn in the part colour
    p.air.append_array(_flips.air)      # (a union never empties a cell; kept for exactness)
    if p.is_empty():
        p.part.append_array(_part_cells())   # flips no cell centre: still show (maybe refused) where it goes
    return p


func execute() -> void:
    if store == null:
        push_error("ConstructionAction.execute(): no store")
        return
    var xform := _xform()
    VoxelImprint.apply(store, material_name, _shape(), xform, CsgState.Op.ADD)
    # Record the placement's identity in the PartIndex sidecar (the field stays pure).
    VoxelEventBusSingleton.emit(
        PartPlacedEvent.CHANNEL,
        PartPlacedEvent.new(VoxelConstants.GRID_ID, _part_cells(), material_name, part.dimensions, xform))


# --- internals ---

func _ensure_flips() -> void:
    if _flips_computed or store == null:
        return
    _lattice        = VoxelImprint.lattice(store, _shape(), _xform(), CsgState.Op.ADD)
    _flips          = _lattice.flips(store)
    _flips_computed = true

# Whether the part's actual (rotated, sub-cell) geometry overlaps or rests on existing solid —
# measured against the brush at the lattice the imprint writes, not against the coarse AABB
# footprint, whose corners a rotated part never reaches.
func _attached() -> bool:
    var inverse := _xform().affine_inverse()
    var shape   := _shape()
    var reach   := _lattice.cell * sqrt(3.0) * 0.5
    for z in _lattice.dim:
        for y in _lattice.dim:
            for x in _lattice.dim:
                var p := _lattice.point(Vector3i(x, y, z))
                if shape.sdf(inverse * p) > reach:
                    continue
                if store.sample(p) < VoxelConstants.SDF_SOLID_THRESHOLD \
                        or store.sample(p + _ATTACH_DOWN) < VoxelConstants.SDF_SOLID_THRESHOLD:
                    return true
    return false

func _basis() -> Basis:
    return VoxelUtils.euler_basis(rotation)

func _shape() -> CsgBoxShape:
    return CsgBoxShape.new(part.dimensions)

# The box brush's world transform: the part's placed pose, with the origin moved from the
# bottom-anchored local origin to the box CENTRE (CsgBoxShape is centred at its origin).
func _xform() -> Transform3D:
    var placed := part.world_transform(_basis(), placement_pos)
    var centre := placed * Vector3(0.0, part.dimensions.y * 0.5, 0.0)
    return Transform3D(_basis(), centre)

# The part's 1m footprint cells — for the PartPlaced sidecar and the ghost of a part that flips
# no cell centre (NOT the safety or attach checks: those read the imprint's field). Uses the AABB
# footprint (footprint_from_aabb collapses a sub-metre-thin dimension to the cell holding its
# midpoint), so a sub-metre-thin part still has a non-empty 1m footprint. The actual geometry is
# written sub-metre by VoxelImprint; this is the coarse tracking footprint.
func _part_cells() -> Array[Vector3i]:
    if _cells_computed:
        return _cells
    _cells_computed = true
    _cells = VoxelUtils.footprint_from_aabb(_xform() * _shape().local_aabb())   # world AABB of the placed box
    return _cells
