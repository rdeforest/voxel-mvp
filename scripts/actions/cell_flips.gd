class_name CellFlips
extends RefCounted

# The cells an edit flips between solid and air, judged at each cell's sample point
# (VoxelUtils.sample_point). One answer shared by an action's preview ghost and its
# voxel_added / voxel_removed events, so both describe the cells the SDF write actually changed —
# not a parallel guess at them. (Player safety asks the written field directly —
# PlayerSafeAction.endangered_by — since sub-cell geometry can flip no cell at all.)
#
# Two ways to get one: SdfLattice.flips() PREDICTS it from the field an edit will write (for
# previews, before anything is written); SdfLattice.write() MEASURES it across the real write (for
# events — the ground truth the structural sim tracks), and only a measured one fills
# `air_materials` and `changed`.
#
# `changed` means some rewritten cell's sample moved, by any amount. It is not "the corners
# differ": re-representing a coarse or inherited leaf moves samples by ~1e-8, so `changed` can be
# true for a lattice whose SdfLattice.writes is false
# (docs/bugs/closed/edit-store-noop-write-reports-changed.md).

var solid:         Array[Vector3i] = []                  # was air, now solid
var air:           Array[Vector3i] = []                  # was solid, now air
var air_materials: PackedByteArray = PackedByteArray()   # what each `air` cell was made of
var changed:       bool            = false               # the write moved some cell's sample value


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

