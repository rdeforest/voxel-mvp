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
    var cells := _part_cells()
    if cells.is_empty():
        return false
    if player != null and _cells_aabb(cells).has_point(player.global_position):
        return false   # would bury the player
    # Attach if any part cell overlaps existing solid (intersection placement) or rests on
    # solid directly below — refuse a part floating in air.
    for cell in cells:
        if store.sample(Vector3(cell)) < VoxelConstants.SDF_SOLID_THRESHOLD:
            return true
        if store.sample(Vector3(cell + Vector3i.DOWN)) < VoxelConstants.SDF_SOLID_THRESHOLD:
            return true
    return false


func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.part    = _part_cells()
    p.refused = not validate()
    return p


func execute() -> void:
    if store == null:
        push_error("ConstructionAction.execute(): no store")
        return
    var shape := _shape()
    var xform := _xform()
    var work  := VoxelImprint.compute(store, shape, xform, CsgState.Op.ADD)
    VoxelImprint.apply(store, work, material_name, shape, xform, CsgState.Op.ADD)
    # Record the placement's identity in the PartIndex sidecar (the field stays pure).
    VoxelEventBusSingleton.emit(
        PartPlacedEvent.CHANNEL,
        PartPlacedEvent.new(VoxelConstants.GRID_ID, _part_cells(), material_name, part.dimensions, xform))


# --- internals ---

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

# The part's 1m footprint cells — for the placement/attachment check, the ghost, and the
# PartPlaced sidecar. Uses the AABB footprint (footprint_from_aabb collapses a sub-metre-thin
# dimension to the cell holding its midpoint), so a sub-metre-thin part still has a non-empty,
# placeable 1m footprint — the integer-grid SDF test would miss a 0.5m log between sample points.
# The actual geometry is written sub-metre by VoxelImprint; this is the coarse tracking footprint.
func _part_cells() -> Array[Vector3i]:
    if _cells_computed:
        return _cells
    _cells_computed = true
    _cells = VoxelUtils.footprint_from_aabb(_xform() * _shape().local_aabb())   # world AABB of the placed box
    return _cells

func _cells_aabb(cells: Array[Vector3i]) -> AABB:
    var lo := Vector3(cells[0])
    var hi := lo + Vector3.ONE
    for cell in cells:
        lo = lo.min(Vector3(cell))
        hi = hi.max(Vector3(cell) + Vector3.ONE)
    return AABB(lo, hi - lo)
