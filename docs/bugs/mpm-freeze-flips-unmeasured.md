# The MPM freeze announces its write without the cells it flipped

*Filed by Claude (agent), overnight 2026-09-27, while closing `actions-reshape-no-voxel-events`
(Track G2). From reading the code; no test reproduces a wrong outcome yet.*

**Status:** Open. Severity low. Needs a C++ change, which Track E owns tonight.

## Symptom (expected, not reproduced)
Every other write to the store now emits one matter-changed event (`TerrainSdfChangedEvent`)
carrying the cells it flipped, measured across the write. The freeze can't: `MpmStructure._freeze`
calls `MpmSim.rasterize_to_store`, which writes with `EditStore.write_region` and returns only
`{origin, dim}`. So `_announce_freeze` sends the box with an empty `CellFlips`. Consequences:

- **TerrainSupport** learns the frozen cells only from its box scan, which registers exposed solid
  cells as `Stone`, whatever the particles were made of. Interior frozen cells aren't tracked.
- **PartIndex** can't hear a part cell the freeze empties. The deposit is a union
  (`rasterize_region`: `min(existing, particle)`), but it reads the existing field at 1 m lattice
  points and rewrites the region at 1 m, so it can empty a cell. A sub-metre leaf from an earlier
  edit gets flattened to the 1 m trilerp; elsewhere samples move by about 1e-8
  (`closed/edit-store-noop-write-reports-changed.md`). Before 2026-09-27, TerrainSupport's box
  scan re-emitted `voxel_removed` for a tracked cell it found gone air, which reached PartIndex. The
  scan still drops such a record, but nothing tells PartIndex. That narrow path regressed with
  the consolidation.
- **DetachmentScout** ignores MPM events outright, so a cell the freeze empties never seeds a
  flood, and a grounded neighbour that lost its support through it isn't re-checked. Before
  2026-09-27 the timing guard ignored the single-box freeze too, but it reacted to the chunked
  path (`_emit_pending_chunks`, regions over `SINGLE_EMIT_MAX`), which announces after
  `_sim.clear()`; the source filter drops that as well. With measured flips the scout can seed
  from the freeze's air flips the way it does from its own thaw's collateral.
- Consumers that want a trustworthy "what changed" (the doc 22 recorder, the fence-sag reactions)
  can't tell "flipped nothing" from "not measured" on a freeze event.

## Fix
1. `engine/voxel_dc/mpm_couple.cpp`, `MpmSim::rasterize_to_store`: write with
   `store->write_region_flips(sdf, idx, dim, origin, cell)` instead of `write_region`, and copy its
   `solid`, `air`, `air_materials` and `changed` into the returned dictionary beside `origin` and
   `dim`. Measure what it costs a large freeze first: the measured write samples every rewritten
   cell before and after.
2. `MpmStructure._freeze`: build a `CellFlips` from those keys and announce it. The chunked re-mesh
   path splits the region into `CHUNK`³ boxes emitted over several frames. The flips then belong
   to one event for the whole region, and the re-mesh boxes stay separate. That split is a design
   call: either a flips-only event with an empty-footprint box, or give each chunk the flips inside it.
3. `DetachmentScout._on_edit`: seed from an MPM event's measured flips (the solid neighbours of
   its air flips, and its solid flips), as `_seed_collateral` does for the scout's own thaw.
   Measure first that this can't re-flood the pile the freeze just deposited in a loop.
4. Drop the phantom branch in `TerrainSupport._scan_box` once no writer is unmeasured, or keep it
   deliberately as a check and say so.
