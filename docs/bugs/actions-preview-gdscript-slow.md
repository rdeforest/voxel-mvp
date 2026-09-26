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
`scripts/actions/sdf_lattice.gd`, `store_write.gd`, `voxel_imprint.gd`, `cell_flips.gd`, `player_safe_action.gd`;
the shape math the imprint mirrors, `scripts/csg/csg_sdf.gd` and `scripts/csg/shape/`;
`engine/voxel_dc/edit_store.cpp`, `edit_store_predict.cpp`; the gate `test/test_edit_store_predict.gd`;
the bench `scripts/dev/bench_preview_predict.gd`.

## Progress
*Added by Claude (agent), overnight 2026-09-26.*

- [x] A1a — `EditStore.predict_sphere_stamp` / `predict_imprint` / `predict_work`
  (`engine/voxel_dc/edit_store_predict.cpp`) reproduce `SdfLattice.sphere_stamp`,
  `VoxelImprint.lattice`, `StoreWrite.lattice` and `SdfLattice.flips` bit for bit. Gate:
  `test/test_edit_store_predict.gd`, on the game's store under a 2 m / 1 m / 0.5 m / 0.25 m edit history.
- [ ] A1b — switch the callers, port `_compute_work` (bell, flatten) and `_turns_in` so the
  preview's remaining GDScript cost goes too, then re-measure `preview()` against "before".

Lattice + flips, radius 3, same run (`scripts/dev/bench_preview_predict.gd`):

| Stamp | GDScript | C++ |
|---|---|---|
| dig | 0.99 ms | 0.055 ms |
| CSG sphere | 3.40 ms | 0.16 ms |
| raise (175 points) | 0.72 ms | 0.036 ms |
| flatten (23 points) | 0.45 ms | 0.026 ms |

Raise and flatten keep a GDScript cost this does not touch: `_compute_work` takes 0.20 ms (raise) and
0.49 ms (flatten). Flatten's alone is over its 0.23 ms "before" figure, so A1b can't meet the gate for
flatten unless the work generation moves too.

The player-safety check is a second GDScript cost A1a does not touch. `PlayerSafeAction.endangered_by`
runs inside `preview()` for CSG, construction, flatten, raise / lower and fill-voxel. It calls
`SdfLattice.solidifies_in` / `empties_in` (`_turns_in`, `_pieces_1d`), which walk the rewritten leaves
under the capsule and support boxes with a trilerp and a `store.sample` per test point. The same bench,
with the player standing at the brush's edge (boxes over rewritten leaves, nothing endangered, so no
early out), measures it at 0.27 ms (dig lattice), 0.38 ms (CSG sphere) and 0.27 ms (raise). A player
whose boxes miss the lattice costs almost nothing. At the brush's edge it alone exceeds the "before"
figure for raise (0.11 ms) and is well over half of CSG's (0.63 ms), so A1b must move `_turns_in` to C++
alongside the lattice to meet the gate; the byte-identical requirement applies to it as well.
