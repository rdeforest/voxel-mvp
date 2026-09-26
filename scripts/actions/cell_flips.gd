class_name CellFlips
extends RefCounted

# The cells an edit flips between solid and air, judged at each cell's sample point
# (VoxelUtils.sample_point). One answer shared by an action's preview ghost, its player-safety
# refusal, and its voxel_added / voxel_removed events, so all three describe the cells the SDF
# write actually changed — not a parallel guess at them.
#
# Two ways to get one: SdfLattice.flips() PREDICTS it from the field an edit will write (for
# previews and refusals, before anything is written); snapshot() + since() MEASURES it across
# the real write (for events — the ground truth the structural sim tracks).

var solid: Array[Vector3i] = []   # was air, now solid
var air:   Array[Vector3i] = []   # was solid, now air


func is_empty() -> bool:
    return solid.is_empty() and air.is_empty()


# Put the flips on a preview ghost.
func add_to(p: ActionPreview) -> void:
    p.solid.append_array(solid)
    p.air.append_array(air)


# voxel_added for each new-solid cell, voxel_removed for each new-air cell. Call after the
# write: an added cell is tagged with the material the store now holds at its sample point
# (TerrainProbe.material), so the event and the store can't disagree about what it is made of.
func emit(store: EditStore) -> void:
    for cell in solid:
        VoxelEventBusSingleton.emit(
            VoxelAddedEvent.CHANNEL,
            VoxelAddedEvent.new(VoxelConstants.GRID_ID, cell,
                Materials.from_name(MaterialPalette.name_of(TerrainProbe.material(store, cell)))))
    for cell in air:
        VoxelEventBusSingleton.emit(
            VoxelRemovedEvent.CHANNEL,
            VoxelRemovedEvent.new(VoxelConstants.GRID_ID, cell))


func _add(cell: Vector3i, was: float, now: float) -> void:
    var t := VoxelConstants.SDF_SOLID_THRESHOLD
    if was >= t and now < t:
        solid.append(cell)
    elif was < t and now >= t:
        air.append(cell)


# Before-state of `cells` (cell -> SDF at its sample point), taken just before a write.
static func snapshot(store: EditStore, cells: Array[Vector3i]) -> Dictionary:
    var before := {}
    for cell in cells:
        before[cell] = TerrainProbe.sdf(store, cell)
    return before


# The flips between a snapshot and the store as it is now (after the write).
static func since(store: EditStore, before: Dictionary) -> CellFlips:
    var out := CellFlips.new()
    for cell: Vector3i in before:
        out._add(cell, before[cell], TerrainProbe.sdf(store, cell))
    return out
