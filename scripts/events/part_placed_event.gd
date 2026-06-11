class_name PartPlacedEvent
extends VoxelEvent

# Emitted when a part is imprinted (ConstructionAction). Carries the identity metadata the
# field itself doesn't hold (manifesto #7 sidecar): the part's cells, material, dimensions,
# and placed transform. PartIndex records it; the raw voxel_added events still drive the
# structural/render systems. `ancestry` is the parent part's id, or -1 for a root placement.

const CHANNEL := &"part_placed"

var material:   StringName
var dimensions: Vector3
var transform:  Transform3D
var ancestry:   int


func _init(p_grid_id: int, p_cells: Array[Vector3i], p_material: StringName,
        p_dimensions: Vector3, p_transform: Transform3D, p_ancestry := -1) -> void:
    grid_id    = p_grid_id
    cells      = p_cells
    material   = p_material
    dimensions = p_dimensions
    transform  = p_transform
    ancestry   = p_ancestry
