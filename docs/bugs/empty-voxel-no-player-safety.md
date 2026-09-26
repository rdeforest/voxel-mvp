# EmptyVoxelAction has no player-safety guard; FillAction uses its own clearance check

*Filed by Claude (agent) on 2026-09-25, from the agent review loop that fixed sdf-sample-corner-vs-center and actions-untyped-work-tuple.*

**Status:** Open. Severity low-med.

## Symptom
EmptyVoxel can empty the cell the player is standing on. Other actions check for this through
`PlayerSafeAction.endangered_by(lattice, store)`. That covers Construction, CSG, Bell, Flatten and
FillVoxel.

## Cause
- `scripts/actions/empty_voxel_action.gd:16`: `validate()` never calls `endangered_by`.
- `scripts/actions/fill_action.gd:26-28`: FillAction still uses its own sphere-distance clearance
  (`player.global_position.distance_to(position)`) instead of the shared check against the field it
  writes. That is a second source of truth for "does this edit endanger the player."
- Dig has the same gap and is already tracked in [[dig-action-no-validate-no-safety]].

## Proposed fix
Route EmptyVoxel and Fill through `endangered_by` on the lattice they write. Decide Dig's intent in the
same pass.
