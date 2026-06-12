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


# Imprint the brush into the store at the SUB-METRE leaf (so a sub-metre part is sub-metre solid),
# then emit the structural events at 1m (from the 1m `work`, so the structural system isn't spammed
# with 64x sub-metre events) + terrain_sdf_changed over `box` for the render/collision re-mesh.
# `shape`/`xform`/`op` drive the fine geometry write; `work` (1m) drives the events.
static func apply(store: EditStore, work: Array, material_name: StringName, box: AABB,
        shape: CsgShape, xform: Transform3D, op: int) -> void:
    _imprint_fine(store, shape, xform, op, material_name, box)
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


# Combine the brush's analytic SDF with the store over a dense RENDER_BASE_CELL grid and
# write_region it — the part/CSG geometry at the sub-metre leaf. The brush's own solid region takes
# the part material; existing terrain keeps its material; air is 0 (matches the freeze union rule).
static func _imprint_fine(store: EditStore, shape: CsgShape, xform: Transform3D, op: int,
        material_name: StringName, box: AABB) -> void:
    var inverse := xform.affine_inverse()
    var solid_index := MaterialPalette.index_of(material_name)
    var cell := VoxelConstants.RENDER_BASE_CELL
    var lo := Vector3i((box.position / cell).floor()) - Vector3i.ONE
    var hi := Vector3i(((box.position + box.size) / cell).ceil()) + Vector3i.ONE
    var span := hi - lo
    var dim := maxi(span.x, maxi(span.y, span.z)) + 1
    var sdf := PackedFloat32Array()
    var idx := PackedByteArray()
    sdf.resize(dim * dim * dim)
    idx.resize(dim * dim * dim)
    var i := 0
    for z in dim:
        for y in dim:
            for x in dim:
                var wp := Vector3(lo + Vector3i(x, y, z)) * cell
                var dist := clampf(shape.sdf(inverse * wp), VoxelConstants.SDF_SOLID, VoxelConstants.SDF_AIR)
                var existing := store.sample(wp)
                var combined: float = minf(existing, dist) if op == CsgState.Op.ADD else maxf(existing, -dist)
                sdf[i] = combined
                if op == CsgState.Op.ADD and dist < VoxelConstants.SDF_SOLID_THRESHOLD:
                    idx[i] = solid_index                # the brush is solid here = the placed part
                elif combined < VoxelConstants.SDF_SOLID_THRESHOLD:
                    idx[i] = store.material_at(wp)       # existing terrain keeps its material
                else:
                    idx[i] = 0                           # air
                i += 1
    store.write_region(sdf, idx, dim, Vector3(lo) * cell, cell)
