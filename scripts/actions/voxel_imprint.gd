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


# Imprint the brush into the store at RENDER_BASE_CELL leaves (sub-metre once RENDER_SUBDIV_LOG2 > 0;
# 1 m at the current 0), then emit the structural events for the cells whose sample point the write
# actually flipped (measured across it — the same lattice() field CsgAction predicts from), plus terrain_sdf_changed over
# the rewritten box for the render/collision re-mesh. What the brush makes solid takes the part
# material; existing terrain keeps its material; air is 0 (matches the freeze union rule).
static func apply(store: EditStore, material_name: StringName,
        shape: CsgShape, xform: Transform3D, op: int) -> void:
    var lat := lattice(store, shape, xform, op)
    var inverse := xform.affine_inverse()
    var part := MaterialPalette.index_of(material_name) if op == CsgState.Op.ADD else -1
    var indices := lat.materials(store, part,
        func(c: Vector3) -> bool: return shape.sdf(inverse * c) < VoxelConstants.SDF_SOLID_THRESHOLD, false)
    var before := CellFlips.snapshot(store, lat.cells())
    lat.write(store, indices)
    CellFlips.since(store, before).emit(store)
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, lat.region_lo, lat.region_hi - lat.region_lo))


# The field the imprint writes: the brush's analytic SDF combined with the store over a dense
# RENDER_BASE_CELL lattice covering world_box — union = min(existing, d), subtract = max(existing, -d).
static func lattice(store: EditStore, shape: CsgShape, xform: Transform3D, op: int) -> SdfLattice:
    var inverse := xform.affine_inverse()
    var box := world_box(shape, xform)
    var cell := VoxelConstants.RENDER_BASE_CELL
    var lo := Vector3i((box.position / cell).floor()) - Vector3i.ONE
    var hi := Vector3i(((box.position + box.size) / cell).ceil()) + Vector3i.ONE
    var span := hi - lo
    var dim := maxi(span.x, maxi(span.y, span.z)) + 1
    var origin := Vector3(lo) * cell
    var lat := SdfLattice.new(origin, cell, dim, origin, origin + Vector3.ONE * (float(dim - 1) * cell))
    for z in dim:
        for y in dim:
            for x in dim:
                var i := Vector3i(x, y, z)
                var wp := lat.point(i)
                var dist := clampf(shape.sdf(inverse * wp), VoxelConstants.SDF_SOLID, VoxelConstants.SDF_AIR)
                var existing := store.sample(wp)
                var combined := minf(existing, dist) if op == CsgState.Op.ADD else maxf(existing, -dist)
                lat.sdf[lat.index(i)] = combined
                lat.writes = lat.writes or combined != existing
    return lat
