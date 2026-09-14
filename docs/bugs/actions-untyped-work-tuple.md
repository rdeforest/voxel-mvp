# Actions: untyped positional work-tuple → previews, safety, and geometry drift apart

**Status:** Deferred (2026-06-22). Diagnosed by code review. Structural smell, not a single visible bug —
it's the *reason* several action bugs exist independently.

## Symptom
Within one action, three different cell sets are in play: the preview ghost, the structural events, and the
actual SDF write — and they can cover different cells. The danger/safety checks run at 1 m corner-sample
granularity while the geometry is written sub-metre, so a thin edit that carves a support box at sub-cell
resolution (without flipping a 1 m corner sample) slips past the guard.

## Cause
Actions pass work around as an **untyped positional `Array`** whose layout differs per file:
`entry[1]` means "new SDF" in `csg_action.gd` but "plane_dist" in `flatten_action.gd:114`. Because there's
no shared type, `_endangers()` is reimplemented three times (`bell_sculpt_action.gd:92`,
`flatten_action.gd:65`, `csg_action.gd:83`), each over a differently-shaped tuple. The positional indices
also force explanatory comments (`csg_action.gd:50,52`) that a named field would delete.

Concrete divergences:
- Construction `preview()` returns the coarse footprint AABB (`_part_cells`), `execute()` writes the rotated
  sub-metre brush (`_imprint_fine`), and the structural events come from a *third* set (corner-sampled
  `VoxelImprint.compute`). `construction_action.gd:54` vs `voxel_imprint.gd:67-96` vs `:53-58`.
- CSG `_endangers()`/preview iterate `VoxelImprint.compute`'s 1 m corner work; `execute()` writes
  `_imprint_fine` sub-metre. `csg_action.gd:84-91`.
- `VoxelImprint.compute` early-outs on `is_equal_approx(combined, existing)` (`voxel_imprint.gd:35`), so a
  grazing sub-epsilon edit is dropped from the work set (no event, no danger check) even though
  `_imprint_fine` still writes it.

## Proposed fix
Define a typed work record (e.g. `RefCounted` with `cell`, `new_sdf`, `was_solid`, `now_solid`) as the
single currency between `compute`/`preview`/`execute`/danger checks. Have all three consume the *same* set,
sampled at the *same* sub-cell point (ties into [[sdf-sample-corner-vs-center]]). Collapse the three
`_endangers()` copies into one.

## References
`scripts/actions/voxel_imprint.gd`, `csg_action.gd`, `flatten_action.gd`, `bell_sculpt_action.gd`,
`construction_action.gd`. Related: [[sdf-sample-corner-vs-center]], [[construction-bury-check-single-point]].
