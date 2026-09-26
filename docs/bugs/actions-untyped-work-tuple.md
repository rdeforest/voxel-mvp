# Actions: untyped positional work-tuple → previews, safety, and geometry drift apart

**Status:** Deferred (2026-06-22). Diagnosed by code review. Structural smell, not a single visible bug —
it's the *reason* several action bugs exist independently.

## Symptom (as filed; mostly resolved 2026-09-25 — see below)
~~Within one action, three different cell sets are in play: the preview ghost, the structural events, and
the actual SDF write — and they can cover different cells. The danger/safety checks run at 1 m
corner-sample granularity while the geometry is written sub-metre, so a thin edit that carves a support box
at sub-cell resolution (without flipping a 1 m corner sample) slips past the guard.~~ Resolved except for
Construction's ghost (below).

## Cause
Actions pass work around as an **untyped positional `Array`** whose layout differs per file. That part is
**still open**: `flatten_action.gd` works over `[point, plane_dist, is_solid]` columns and `StoreWrite`
takes `[point, new_sdf]` entries, with no shared type.

Resolved divergences (the code they cite no longer exists):
- ~~`_endangers()` reimplemented three times (bell, flatten, CSG)~~ — now one
  `PlayerSafeAction.endangered_by(flips)`.
- ~~CSG `_endangers()`/preview iterated `VoxelImprint.compute`'s 1 m corner work while `execute()` wrote
  `_imprint_fine` sub-metre~~ — CSG's ghost and refusal now read the same `VoxelImprint.lattice` field
  `apply()` writes.
- ~~`VoxelImprint.compute` early-out on `is_equal_approx(combined, existing)`~~ — gone; CSG refuses only a
  brush that changes no stored value (`SdfLattice.writes`).
- ~~Construction's structural events came from a third, corner-sampled set~~ — events are now the measured
  flips of the write.

**Still open:** the untyped tuples above, and Construction `preview()` still returns the coarse footprint
(`_part_cells`) rather than the flips of the imprint it writes.

(*Status update drafted by Claude.*) Every action's preview, player-safety refusal and voxel events now
come from one `CellFlips` — the cells whose centre sample flips — predicted from the `SdfLattice` each
action writes (`scripts/actions/sdf_lattice.gd`) and, for events, measured across that write.

## Proposed fix
Define a typed work record (e.g. `RefCounted` with `cell`, `new_sdf`, `was_solid`, `now_solid`) as the
single currency between `compute`/`preview`/`execute`/danger checks. Have all three consume the *same* set,
sampled at the *same* sub-cell point (now `VoxelUtils.sample_point`, the cell centre).

## References
`scripts/actions/voxel_imprint.gd`, `csg_action.gd`, `flatten_action.gd`, `bell_sculpt_action.gd`,
`construction_action.gd`, `cell_flips.gd`, `sdf_lattice.gd`. Related: [[construction-bury-check-single-point]].
