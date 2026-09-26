# `EditStore::stamp_sphere` / `stamp_box` UNION repaints terrain the brush didn't make

*Filed by Claude (agent), overnight 2026-09-26, while fixing the `SdfLattice.materials()` owner-leaf
seam (Track E1). From reading the code; no test has run this case.*

**Status:** Open. Severity low (latent: no game path calls these; tests and `scripts/dev` do). Needs
Robert's call on intent.

## Symptom
A UNION `stamp_sphere` / `stamp_box` sets its material on every write leaf that ends with any solid corner,
including a leaf that was already solid terrain and that the brush never reaches. The GDScript write paths
(`SdfLattice.materials()`, used by `FillAction` and `VoxelImprint`) paint only leaves where the edit made a
corner solid, and keep existing terrain's material. The same brush therefore paints differently depending on
which path wrote it.

## Cause
`EditStore::_stamp_region` (engine/voxel_dc/edit_store.cpp, the write-leaf branch): `any_solid` is taken from
the post-union corner value `after = MIN(before, b)`, and `if (any_solid && op == 0)` sets `n.material`. It
never asks whether `b` (the brush) or the change from `before` made that corner solid.

## Callers
`test/test_mpm_couple.gd`, `test/test_ground_flood.gd`, `test/test_detachment_scout.gd`,
`test/test_cell_sample_convention.gd`, `scripts/dev/bench_mpm_thaw_work.gd`. None of them looks at the
material of terrain adjacent to the stamp, so none pins either rule.

## Question
Are `stamp_sphere` / `stamp_box` test and debug tools whose paint rule doesn't matter, or should they match
`materials()` (paint only where `after < 0 && (b < 0 || before >= 0)`)? If they should match, the change is
one condition in `_stamp_region` plus a test that stamps next to solid terrain of another material. Related:
[single-voxel-edits-unexpected](single-voxel-edits-unexpected.md) (paint findings, question 5).
