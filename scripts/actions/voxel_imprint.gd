class_name VoxelImprint
extends RefCounted

# Imprint an analytic CSG brush (a CsgShape at a world transform) into the EditStore. This
# is the shared core of CsgAction (player CSG primitives) and ConstructionAction (parts as
# voxels) — a part placement and a CSG box stamp are the same operation: a brush combined
# into the field. The brush's identity is discarded; only the modified field remains
# (docs/roadmap/design/03-dc-qef-geometry.md §4 "Imprinting, not CSG").

const MARGIN := 2.0   # cells of band evaluated beyond the shape, for a clean zero-crossing


# World AABB the brush touches: its local AABB rotated into world by `xform`, grown so the
# surface band is written on every side.
static func world_box(shape: CsgShape, xform: Transform3D) -> AABB:
    return (xform * shape.local_aabb()).grow(MARGIN)


# Per-cell change over the brush's world box, combining the brush's signed distance with the
# store's current field: [[Vector3i cell, float new_sdf, bool was_solid, bool now_solid], ...]
# op is CsgState.Op (ADD = union/min, SUBTRACT = difference/max). Only cells that actually
# change are returned.
static func compute(store: EditStore, shape: CsgShape, xform: Transform3D, op: int) -> Array:
    var inverse := xform.affine_inverse()
    var box := world_box(shape, xform)
    var work: Array = []
    VoxelUtils.for_each_in_bounding_box(
        box.position,
        box.size,
        func(cell: Vector3i) -> void:
            var distance := shape.sdf(inverse * Vector3(cell))
            distance = clampf(distance, VoxelConstants.SDF_SOLID, VoxelConstants.SDF_AIR)
            var existing := store.sample(Vector3(cell))
            var combined := minf(existing, distance) if op == CsgState.Op.ADD else maxf(existing, -distance)
            if is_equal_approx(combined, existing):
                return
            var was_solid := existing  < VoxelConstants.SDF_SOLID_THRESHOLD
            var now_solid := combined  < VoxelConstants.SDF_SOLID_THRESHOLD
            work.append([cell, combined, was_solid, now_solid])
    )
    return work


# Write `work` into the store (newly-solid cells take `material_name`; carved cells keep
# their current material), then emit the primitive voxel events + terrain_sdf_changed over
# `box` so the structural system tracks the change and the render/collision re-mesh.
static func apply(store: EditStore, work: Array, material_name: StringName, box: AABB) -> void:
    var solid_index := MaterialPalette.index_of(material_name)
    StoreWrite.cells(store, work, func(entry): return solid_index if entry[3] else -1)
    var material := Materials.from_name(material_name)
    for entry in work:
        var cell: Vector3i = entry[0]
        if entry[3] and not entry[2]:
            VoxelEventBusSingleton.emit(VoxelAddedEvent.CHANNEL,   VoxelAddedEvent.new(VoxelConstants.GRID_ID, cell, material))
        elif entry[2] and not entry[3]:
            VoxelEventBusSingleton.emit(VoxelRemovedEvent.CHANNEL, VoxelRemovedEvent.new(VoxelConstants.GRID_ID, cell))
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, box.position, box.size))
