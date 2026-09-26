# Action previews got 5–10× slower: the exact field prediction runs in GDScript every frame

*Filed by Claude (agent) on 2026-09-25, from the agent review loop that fixed sdf-sample-corner-vs-center and actions-untyped-work-tuple.*

**Status:** Open, **next up**, ahead of FEAT089. A perf regression introduced by `f11d284`, which
fixed `sdf-sample-corner-vs-center`. It is not accepted as the price of exactness.

## Symptom
Measured for a radius-3 brush on real terrain, as time per `preview()` call. The renderer calls it every frame.

| Action | Before | After |
|---|---|---|
| dig / fill | 0.07 ms | 0.76 ms |
| raise | 0.11 ms | 0.65 ms |
| flatten | 0.23 ms | 0.73 ms |
| CSG sphere | 0.63 ms | 2.5 ms |

## Cause
Previews now predict the exact field the write lays down (`SdfLattice`) rather than testing corners. That is
correct, and it is the fix. The cost is GDScript overhead. Building the lattice takes about 1000–2200
`store.sample` / `shape.sdf` calls, plus one trilerp per cell in `SdfLattice.flips`.
`scenes/player/voxel_preview_renderer.gd:78` calls `action.preview()` every frame.

## Proposed fix
Build the lattice and its flip set in C++, as a new `EditStore` method that returns the predicted field and flips
for a sphere or shape stamp. That keeps the prediction exact and drops the GDScript loop. A byte-identical
test against the current GDScript `SdfLattice` gates it.

Rejected: caching the preview in `voxel_preview_renderer` while the aim and parameters don't change. It
hides the cost only while the player holds still; aiming is when previews matter.

## References
`scripts/actions/sdf_lattice.gd`, `store_write.gd`, `voxel_imprint.gd`, `engine/voxel_dc/edit_store.cpp`.
