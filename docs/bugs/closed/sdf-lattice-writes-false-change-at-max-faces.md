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

