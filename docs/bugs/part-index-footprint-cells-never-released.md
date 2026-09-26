# PartIndex can hold footprint cells the imprint never made solid, so a part record never dies

*Filed by Claude (agent) on 2026-09-25, from the agent review loop that fixed sdf-sample-corner-vs-center and actions-untyped-work-tuple.*

**Status:** Open. Severity low-med. It's the same kind of drift that `actions-untyped-work-tuple`
fixed, but outside preview, events and safety.

## Symptom
A part whose AABB footprint includes cells the rotated imprint never fills keeps those cells in
PartIndex after everything it really occupies has been carved away. The record outlives the part.

## Cause
- `ConstructionAction` still sends the coarse footprint
  (`VoxelUtils.footprint_from_aabb`, `scripts/actions/construction_action.gd:131`) in the
  PartPlaced sidecar. Preview, safety, attachment and events all use the imprint's real flips.
- `PartIndex` releases a cell only on `voxel_removed` (`scripts/structural/part_index.gd:33-46`).
  A footprint cell that was never solid is never removed, so it is never released.

## Proposed fix
Register a part under the cells its imprint actually flips solid, the same set as its events. Keep a
footprint only where a coarse proxy is truly needed, such as the empty-flip ghost fallback.
