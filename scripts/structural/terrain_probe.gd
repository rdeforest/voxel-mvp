class_name TerrainProbe

# Shared per-cell reads of the EditStore, all at the cell's sample point
# (VoxelUtils.sample_point — the cell centre). Every "is this cell solid / what is it made of"
# question goes through here, so structural tracking, actions, previews and MPM classify a
# boundary cell identically and a sampling-convention change lands in one place.

static func sdf(store: EditStore, cell: Vector3i) -> float:
    return store.sample(VoxelUtils.sample_point(cell))

static func is_solid(store: EditStore, cell: Vector3i) -> bool:
    return sdf(store, cell) < VoxelConstants.SDF_SOLID_THRESHOLD

static func material(store: EditStore, cell: Vector3i) -> int:
    return store.material_at(VoxelUtils.sample_point(cell))

static func is_bedrock(store: EditStore, cell: Vector3i) -> bool:
    return material(store, cell) == MaterialPalette.BEDROCK
