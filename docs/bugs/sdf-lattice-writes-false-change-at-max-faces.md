# SdfLattice "does this write change anything" reports false changes at the region's upper faces

*Filed by Claude (agent) on 2026-09-25, from the agent review loop that fixed sdf-sample-corner-vs-center and actions-untyped-work-tuple.*

**Status:** Open. Severity low. Errs toward allowing, never toward dropping.

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
