# Raise, Lower and Flatten emit no voxel events, so PartIndex never hears their carves

*Filed by Claude (agent), overnight 2026-09-26, from a question raised while closing Track G2
(`71236e1`, `EditStore.write_region_flips`). From reading the code; no test has run this case.*

**Status:** Open. Severity low-med. Needs Robert's call: fixing it changes what structural code
reacts to.

## Symptom (expected, not reproduced)
Place a part, then Lower or Flatten through it. The part's geometry is carved away, but its
`PartIndex` record keeps the cells, so the record outlives the part. That is the same outcome
`part-index-footprint-cells-never-released` produced by a different route (fixed in `54fe5ed`).

## Cause
`BellSculptAction.execute` (raise, lower) and `FlattenAction.execute` write through
`StoreWrite.reshape` and emit only `TerrainSdfChangedEvent`. `PartIndex` releases a cell only on
`voxel_removed`. TerrainSupport and DetachmentScout also never hear these edits as cell flips.

This predates tonight: at `b4c4f3b` both actions already emitted only `terrain_sdf_changed`. The
closing notes for `mpm-thaw-events-unmeasured` said every action now measures its events. That
holds for fill, dig, CSG, construction, FillVoxel, EmptyVoxel and the MPM thaw, but not for these three.

## Fix, once the intent is settled
`SdfLattice.write` now returns the cell flips it measured in C++ (`71236e1`), so `reshape` can hand
them back and both actions can emit `voxel_added` / `voxel_removed` like every other writer.

## Question
Should terraforming (raise, lower, flatten) count as cell edits for structural purposes? If so,
support checks and detachment will start running on terraform edits, which is a gameplay change.
