# EditStore: a 1 m lattice write flattens finer leaves inside it

*Filed by Claude (agent) on 2026-09-27 (overnight Track E5), from a reviewer's question on the
thaw-carve solve and a headless probe.*

**Status:** Open, latent. Severity low today: every writer works at 1 m (`RENDER_SUBDIV_LOG2 = 0`, so
`RENDER_BASE_CELL = 1.0`) and no sub-metre leaves exist in a live store. It bites the first time
anything makes them.

## Symptom
`write_region` at `cell = 1.0` writes every leaf overlapping the region, including leaves finer than
the cell, from the 1 m array's trilerp (`edit_store.cpp` `_write_region`, `is_write_leaf` is
`s <= cell`). Sub-metre detail inside the box is lost, and nothing reports it: the flips are judged at
1 m cell centres, so a feature that moves no centre's side is invisible to them and to any events.

Probe (a reviewer's headless harness, not kept; flat-ground store): `stamp_sphere` at (0.3, 10.4, 0.3), r 0.35, `min_leaf` 0.125
reads −0.252 at its centre (material 2). A 5³ `write_region` at 1 m over it, every lattice value set
to the store's current sample at that point, leaves it reading +7.529 (material 0). The sphere is
gone although every 1 m value was kept.

## Where
Every 1 m lattice writer: `StoreWrite.write` (thaw, fill/empty voxel, reshape actions),
`MpmSim.rasterize_to_store`, and `EditStore.predict_carve` (which rewrites a cube, so a flat plan
covers far more than its span).

## Fix
Not designed. Either the write keeps leaves finer than its cell whose values it doesn't need to
change (a write that re-represents rather than resamples), or writers work at the finest resolution
present in their box. Violates edits-first-class once finer leaves exist; needs a decision before
`RENDER_SUBDIV_LOG2` goes above 0.
