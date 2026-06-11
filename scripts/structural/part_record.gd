class_name PartRecord
extends RefCounted

# One placed part's identity, held in the PartIndex sidecar (not in the voxel field). The
# field carries SDF + material; this carries who/what/where + lineage, so queries like
# "every part descended from ancestor X" work without polluting the voxel data.

var id:         int
var cells:      Array[Vector3i]   # the part's currently-live voxels (shrinks as they're carved)
var material:   StringName
var dimensions: Vector3
var transform:  Transform3D
var ancestry:   int               # parent part id; -1 for a root placement


func _init(p_id: int, p_cells: Array[Vector3i], p_material: StringName,
        p_dimensions: Vector3, p_transform: Transform3D, p_ancestry: int) -> void:
    id         = p_id
    cells      = p_cells
    material   = p_material
    dimensions = p_dimensions
    transform  = p_transform
    ancestry   = p_ancestry
