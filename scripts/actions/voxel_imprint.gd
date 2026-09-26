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
# Returns those measured flips, so a caller that tracks what the write did (PartIndex, via
# ConstructionAction) reads the very set the events carried instead of measuring it again.
static func apply(store: EditStore, material_name: StringName,
        shape: CsgShape, xform: Transform3D, op: int) -> CellFlips:
    var lat := lattice(store, shape, xform, op)
    var part := MaterialPalette.index_of(material_name) if op == CsgState.Op.ADD else -1
    var indices := lat.materials(store, part, false)
    var before := CellFlips.snapshot(store, lat.cells())
    lat.write(store, indices)
    var flips := CellFlips.since(store, before)
    flips.emit(store)
    VoxelEventBusSingleton.emit(
        TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, lat.region_lo, lat.region_hi - lat.region_lo))
    return flips


# The field the imprint writes: the brush's analytic SDF combined with the store over a dense
# RENDER_BASE_CELL lattice covering world_box — union = min(existing, d), subtract = max(existing, -d).
# EditStore evaluates the brush from the shape's sdf_kind() / sdf_dims() (its mirror of CsgSdf).
static func lattice(store: EditStore, shape: CsgShape, xform: Transform3D, op: int) -> SdfLattice:
    return SdfLattice.predicted(store.predict_imprint(shape.sdf_kind(), shape.sdf_dims(), xform, op,
        VoxelConstants.RENDER_BASE_CELL))
