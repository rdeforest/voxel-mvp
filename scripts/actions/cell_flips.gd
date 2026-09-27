class_name CellFlips
extends RefCounted

# The cells an edit flips between solid and air, judged at each cell's sample point
# (VoxelUtils.sample_point). One answer shared by an action's preview ghost and its matter-changed
# event (TerrainSdfChangedEvent.flips), so both describe the cells the SDF write actually changed —
# not a parallel guess at them. (Player safety asks the written field directly —
# PlayerSafeAction.endangered_by — since sub-cell geometry can flip no cell at all.)
#
# Two ways to get one: SdfLattice.flips() PREDICTS it from the field an edit will write (for
# previews, before anything is written); measured() reads what EditStore MEASURED across the real
# write (SdfLattice.write, the MPM freeze; for the event — the ground truth the structural sim
# tracks), and only a measured one fills `air_materials` and `changed`.
#
# `changed` means some rewritten cell's sample moved, by any amount. It is not "the corners
# differ": re-representing a coarse or inherited leaf moves samples by ~1e-8, so `changed` can be
# true for a lattice whose SdfLattice.writes is false
# (https://github.com/rdeforest/voxel-mvp/issues/26).

var solid:         Array[Vector3i] = []                  # was air, now solid
var air:           Array[Vector3i] = []                  # was solid, now air
var air_materials: PackedByteArray = PackedByteArray()   # what each `air` cell was made of
var changed:       bool            = false               # the write moved some cell's sample value


# What EditStore measured across a write (write_region_flips, or MpmSim.rasterize_to_store, which
# returns its keys): none when the write was refused and returned nothing.
static func measured(d: Dictionary) -> CellFlips:
    var out := CellFlips.new()
    if not d.has("solid"):
        return out

    out.solid         = d.solid
    out.air           = d.air
    out.air_materials = d.air_materials
    out.changed       = d.changed
    return out


func is_empty() -> bool:
    return solid.is_empty() and air.is_empty()


# Put the flips on a preview ghost.
func add_to(p: ActionPreview) -> void:
    p.solid.append_array(solid)
    p.air.append_array(air)

