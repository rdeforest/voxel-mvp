# A refused preview reads the generator twice per lattice point

*Filed by Claude (agent), overnight 2026-09-26, while closing chunk A4 of
`sdf-lattice-writes-false-change-at-max-faces` (fixed in `af19749`)
(its "Follow-up" section has the measurements).*

**Status:** Open, **left as is until the volumetric generator lands** (decided 2026-09-27; see
*Decision*). Severity low (perf; ~0.05 ms per no-op-looking preview against a 20 ms frame).

## Symptom
A CSG union buried in unedited ground previews in ~0.34 ms (`scripts/dev/bench_lattice_writes.gd`,
"union buried in ground"). The dry run is 0.126 ms of that; the rest is the lattice build a real stamp
also pays.

## Cause
The build reads the store at every lattice point (`fill` in
`engine/voxel_dc/edit_store_lattice.h`, via `sample_toward`, which calls the generator for an unedited
leaf). When no point's float32 changed, `prediction()` settles it with `EditStore::lattice_writes`
(`engine/voxel_dc/edit_store_dry_run.cpp`), which calls the generator again at the same 2,744 points.
Estimated saving: 2,744 calls × ~16.5 ns ≈ 0.045 ms (per-call cost measured on the pre-A4 dry run, not
re-measured).

## Options
- Hand the build's reads to the dry run (an internal overload of `lattice_writes` that the builders call,
  keeping the standalone binding). Couples every lattice builder to the dry run's internals.
- Cache the generator per column (it is `y - surface(x, z)` today). Breaks when the planned volumetric
  generator lands, since that is not a heightfield.
- Leave it: at this size it is well under budget.

## Decision (2026-09-27)
*Recorded by Claude from Robert's answer to Q13 in
[`overnight-2026-09-26-questions.md`](../roadmap/implementation/done/overnight-2026-09-26-questions.md).*

Leave it. Robert agreed with revisiting when the volumetric generator
([doc 19](../roadmap/design/19-volumetric-worldgen.md)) replaces the heightfield, since the
generator's per-call cost, and so this whole cost profile, changes then. (Claude's expectation, not
his: the bigger work may moot it.) Re-measure `bench_lattice_writes.gd` "union buried in ground" on the new generator
before choosing a fix.
