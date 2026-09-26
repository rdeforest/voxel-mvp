class_name LatticeEdit
extends RefCounted

# One entry of a StoreWrite: a new SDF value at a store LATTICE point (a leaf corner, not a cell),
# and optionally the material of the leaf whose origin is that point. The typed currency the
# GDScript work-set writers (FillVoxel, EmptyVoxel, MPM carve) hand StoreWrite, which turns a
# set of these into the SdfLattice that is both written and flip-tested — so an action's preview,
# refusal and events all derive from this one work set. What it does to CELLS is
# StoreWrite.lattice(store, work).flips(store) (a CellFlips).

var point:    Vector3i   # store lattice point
var sdf:      float      # value written there
var material: int        # material for the leaf with origin `point`; < 0 keeps its current one


func _init(p_point: Vector3i, p_sdf: float, p_material: int = -1) -> void:
    point    = p_point
    sdf      = p_sdf
    material = p_material
