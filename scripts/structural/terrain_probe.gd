class_name TerrainProbe

# Shared solidity / bedrock tests over the EditStore, sampled at the 1 m cell centre.
# These predicates were copy-pasted across GroundFlood, DetachmentScout, and FloodViz;
# single-sourced here so a sampling-convention change lands in one place.

static func is_solid(store: EditStore, cell: Vector3i) -> bool:
    return store.sample(Vector3(cell) + VoxelConstants.VOXEL_CENTER_OFFSET) < VoxelConstants.SDF_SOLID_THRESHOLD

static func is_bedrock(store: EditStore, cell: Vector3i) -> bool:
    return store.material_at(Vector3(cell) + VoxelConstants.VOXEL_CENTER_OFFSET) == MaterialPalette.BEDROCK
