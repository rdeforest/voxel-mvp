extends RefCounted

# FillVoxel / EmptyVoxel as they were before f11d284 (git show f11d284^:scripts/actions/
# fill_voxel_action.gd), for probe_single_voxel.gd's comparison: solidity read at the cell's
# minimum CORNER, and the write sets that one lattice point to SDF_SOLID / SDF_AIR (the target
# leaf takes the material on a fill). Same StoreWrite path, so only the rule differs.

var cell:     Vector3i
var store:    EditStore
var solid:    bool
var material: int


func _init(p_cell: Vector3i, p_store: EditStore, p_solid: bool, p_material: int) -> void:
    cell     = p_cell
    store    = p_store
    solid    = p_solid
    material = p_material


func refusal() -> String:
    if (store.sample(Vector3(cell)) < VoxelConstants.SDF_SOLID_THRESHOLD) == solid:
        return "already_solid" if solid else "already_air"
    return ""


func validate() -> bool:
    return refusal() == ""


func _work() -> Array[LatticeEdit]:
    var sdf := VoxelConstants.SDF_SOLID if solid else VoxelConstants.SDF_AIR
    var work: Array[LatticeEdit] = [LatticeEdit.new(cell, sdf, material if solid else -1)]
    return work


func execute() -> void:
    StoreWrite.cells(store, _work())
