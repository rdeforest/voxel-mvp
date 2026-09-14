# SDF sampling: cell corner vs. cell center, inconsistent across the codebase

**Status:** Deferred (2026-06-22). Diagnosed by code review (three independent passes converged on it),
not yet reproduced in-game. Pervasive — touches actions, structural tracking, and previews.

## Symptom (expected, not yet captured)
Edit previews and `voxel_added`/`voxel_removed` events are shifted ~½ cell from what the SDF write
actually changes; boundary voxels get classified solid-vs-air differently by different subsystems looking
at the *same* cell. Likely contributes to boundary mis-tracking and possibly some inside-coverage cracks.

## Root cause (precise)
There is **no single source of truth for "which point represents a cell."** Two conventions coexist:

- **Corner** — `store.sample(Vector3(cell))` (the cell's minimum corner):
  - `scripts/actions/dig_action.gd:39,61`, `scripts/actions/fill_action.gd:44,72` —
    `VoxelUtils.is_in_sphere(Vector3(cell), position, radius)`.
  - `scripts/structural/terrain_support.gd:30,52,177`.
  - `scripts/actions/construction_action.gd:45,47` and the CSG danger check — 1 m corner samples.
- **Center** — `Vector3(cell) + VOXEL_CENTER_OFFSET` (confirmed = 0.5 on each axis,
  `scripts/voxel_constants.gd:13`):
  - `scripts/structural/terrain_probe.gd:8,11`.
  - `scripts/structural/mpm_structure.gd:96,160`.
  - `PlayerSafeAction.buries/drops` (`scripts/actions/player_safe_action.gd:29,34`).

For any cell straddling the zero-crossing, corner and center can fall on opposite sides → the same voxel is
solid to one subsystem and air to another. Worse, the actions test corners but **write** an analytic
world-space sphere (`store.stamp_sphere(position, radius)`, `dig_action.gd:52`, `fill_action.gd:61`), which
modifies the field wherever the sphere reaches — so the highlighted/evented cell set is systematically
½-cell off the changed set: `+`-side edge cells missed, `-`-side cells spuriously included.

A secondary off-by-one compounds it: `VoxelUtils.is_in_sphere` uses `distance <= radius` (inclusive,
`voxel_utils.gd:41`) while `for_each_in_bounding_box` walks `range(floor, ceil)` (half-open,
`voxel_utils.gd:14-24`), so the corner at exactly `position+radius` is never visited.

## Proposed fix
Pick **one** convention (center is the natural choice — it's what solidity/containment logic already
assumes) and route every cell→sample-point through a single shared helper. The sphere-cell-walk
(`origin = pos - ONE*radius` + `for_each_in_bounding_box` + `is_in_sphere`) is currently copy-pasted across
dig/fill/bell; centralizing it makes this a one-line fix instead of three, and lets the brush *test* match
the brush *write* (sample the same sub-cell point the analytic stamp uses).
- **Gate:** a headless test that the evented cell set equals the set of cells whose SDF sign actually
  flipped after `stamp_sphere`, for a brush straddling cell boundaries.

## References
`scripts/voxel_constants.gd` (`VOXEL_CENTER_OFFSET`); `scripts/voxel_utils.gd` (the shared walk to
centralize); [[dc-inside-coverage-cracks]] (a possible downstream symptom).
