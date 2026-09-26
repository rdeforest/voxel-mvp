# SdfLattice "does this write change anything" reports false changes at the region's upper faces

*Filed by Claude (agent) on 2026-09-25, from the agent review loop that fixed sdf-sample-corner-vs-center and actions-untyped-work-tuple.*

**Status:** **CLOSED — fixed** on `perf/preview-lattice-cpp` (chunk A2, overnight 2026-09-26). Kept for
the diagnosis: the report found one of three defects in the flag. See Resolution.

## Symptom
A CSG ADD into air, where the terrain SDF is above `SDF_AIR`, always counts as a change. So
repeating an identical CSG stamp there is never refused as a no-op.

## Cause
The "writes anything" test compares the predicted lattice against `store.sample`. At a point on the
region's upper boundary (its max faces), `store.sample` reads the neighbouring leaf, which the write
doesn't touch. The comparison therefore sees a difference that the write doesn't make. The flag is
set in `scripts/actions/voxel_imprint.gd:60` (`lat.writes = lat.writes or combined != existing`) and
drives CSG's `_writes` refusal (`scripts/actions/csg_action.gd:23,47`).

## Proposed fix
Compare the lattice against the stored leaf values the write replaces, owned by the rewritten leaf,
rather than a point sample that can land in the neighbouring leaf. Add a test that re-stamps an
identical CSG add into air and expects a refusal.

## Resolution
*Drafted by Claude (agent), overnight 2026-09-26.*

After A1 the flag lived in C++ (`edit_store_lattice.h` `fill`, and `edit_store_predict_work.cpp`). Three
defects, each pinned by `test/test_lattice_writes.gd`. Three of its tests fail on the old code: the identical
CSG re-stamp refusal, the identical sphere stamp, and the union keeping the owned max-face value.
`test_change_only_at_a_max_face_counts` guards the other direction (an over-correction that stops counting
max-face changes); by reading the old code it passes there too, since the old flag erred toward true.

1. **Max faces (the report).** `fill` read "before" with `store.sample`, which on a node mid-plane takes the
   upper child, so a max-face point read the untouched neighbour. That also made the *written* value wrong,
   not just the flag: a union combined with the neighbour's value, so it could raise the rewritten leaf's own
   corner (owned 1.0, neighbour deep air, brush 3.0 → the old code wrote 3.0). Fix:
   `EditStore.sample_toward(p, toward)` breaks mid-plane ties toward `toward`; builders pass the centre of the
   rewritten leaf that owns the point (`Lattice::owner_centre`). `sample(p)` is `sample_toward(p, p)`.
2. **Float32.** The flag compared the double `after` with the double `before`. A stored corner is float32, so
   an identical re-stamp whose brush wins at a point (`min(float(d), d) = d`) looked like a change even away
   from the faces. Now `float(after) != float(before)`; the work lattice compares `float(sdf)` likewise.
3. **Leaves other than the one read.** A lattice point is a corner of up to eight rewritten leaves, and a leaf
   finer than the cell has corners that are not lattice points. A lattice that matches every leaf it was read
   from can still heal a seam an earlier write left at its region faces, or flatten finer detail.
   `EditStore.lattice_writes` is `_write_region` as a dry run (same descent, coarser leaves split with the
   shared `child_corners`, unedited leaves read from the generator), returning at the first changed corner.
   Predictions call it only when every point matched, so a real edit pays nothing for it.

Flag semantics now: true iff the write changes some stored corner's float32 SDF. An unedited leaf whose
corners the write sets to the generator's own values counts as unchanged, although the leaf goes from
generator to trilerp inside. Material is not considered: see
[csg-restamp-material-only-refused](../csg-restamp-material-only-refused.md).

Cost, radius-3 CSG sphere preview on the game store (`scripts/dev/bench_lattice_writes.gd`): a real stamp
0.22 ms, no dry run. Refused previews: identical re-stamp in air 0.41 ms (dry run 0.13), union buried in
ground 0.69 ms (dry run 0.51, the generator at 8 corners per unedited leaf). The descent rewrite
(`upper_side`) made previews on an edited store faster than before: 0.36 → 0.22 ms. Other previews did not
change (`bench_preview_predict`: dig 0.058, CSG 0.169 ms).


## Follow-up: the dry run's repeated reads (chunk A4)
*Drafted by Claude (agent), overnight 2026-09-26.*

The buried case's cost was measured, not assumed. Doubling each generator call in the old dry run
added 0.29 ms of its 0.47 ms; doubling each array read added 0.115 ms. The buried lattice is 14³
points under 13³ unedited leaves, so the old code ran 8 × 13³ = 17,576 generator calls and 17,576
array trilerps for 2,744 distinct points.

The dry run (now `engine/voxel_dc/edit_store_dry_run.cpp`) keeps two things per lattice point: the
array's float32 value, and whether an unedited leaf's corner there was found unchanged. Neither
depends on which leaf asks, so the next leaf sharing the point reuses them. It shares a point only
when a leaf's corners are that lattice point exactly: each axis's coordinates are checked against a
per-axis table, once per leaf. A leaf finer than the cell, or one past the lattice, takes the old
per-corner path. An edited leaf reuses the array's value but still compares against its own stored
corner. `test_edited_leaf_beside_unedited_ones_is_compared_on_its_own` pins that. It fails if an
edited leaf reuses its unedited neighbour's "unchanged" finding. The answer is unchanged by design.
The three new tests pass on the old code too. What they guard against is a sharing bug. Of two
deliberately broken builds, that test caught one, and five tests caught the other (wrong corner
slots).

Checking the exact coordinates once per corner instead of once per leaf cost ~0.1 ms by itself (dry
run 0.27 ms), so the check is per axis per leaf.

`bench_lattice_writes.gd`, before → after (ms):

| case | preview | dry run alone |
|---|---|---|
| real stamp before any edit | 0.165 → 0.165 | — |
| real stamp at the surface | 0.216 → 0.218 | 0.048 → 0.017 (not run by the preview) |
| re-stamp in air | 0.40 → 0.36 | 0.13 → 0.08 |
| union buried in ground | 0.68 → 0.34 | 0.47 → 0.126 |

"Before" was re-measured on the A2 code (nothing on this path changed since `af19749`); the 0.69 / 0.51
in the close-out above is an earlier run of the same code. The bench prints one mean over 300 reps, and
back-to-back runs of it vary by roughly 5–10%.

`bench_preview_predict.gd` is unchanged (dig 0.057, fill 0.058, raise 0.050, flatten 0.046, CSG sphere
0.165, beam +0 m 0.32, beam +3 m 0.88 ms; the lattice dry run doesn't run for a real edit).

What the buried dry run's 0.126 ms goes on now: 0.034 ms descending the tree and locating slots
(measured by skipping the corner loop). The rest is 2,744 generator calls, 2,744 trilerps and the
per-corner bookkeeping. The larger part of the buried preview is now outside the dry run: ~0.21 ms,
the same lattice build a real stamp pays. That build already reads the generator at every point, so
the dry run's 2,744 generator calls repeat it. Removing that repeat means handing the build's reads to
the dry run, which couples the builders to it (not done; tracked as
[actions-lattice-dry-run-double-generator](../actions-lattice-dry-run-double-generator.md)). A per-column generator cache
(the generator is `y - surface(x, z)`) would also cut calls, but it relies on the generator being a
heightfield, which the planned volumetric generator is not.
