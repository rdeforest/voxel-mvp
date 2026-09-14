# ConstructionAction: "would bury the player" tests one point, not the capsule

**Status:** Deferred (2026-06-22). Diagnosed by code review. Real gap in the refuse-don't-deform guard.

## Symptom
A placed part that imprints across the player's head or feet — but not their body origin — passes
validation and buries them.

## Cause
`scripts/actions/construction_action.gd:40` — the bury test is
`_cells_aabb(cells).has_point(player.global_position)`, a single point (the body origin). The player is a
~0.5 m-radius, ~3 m capsule; `PlayerSafeAction.buries()` (`player_safe_action.gd:29`) checks the whole
capsule box, but Construction reimplements a weaker inline check instead of reusing it.

Compounding it: `_cells_aabb` is the AABB of the *footprint cells* (`footprint_from_aabb`, which collapses
thin axes to one cell), not the true rotated brush — so for a thin or angled part the bury-box is further
off from the actual geometry.

## Proposed fix
Use the shared `PlayerSafeAction.buries()` capsule test (the same one Fill/Bell/Flatten use), against the
actual imprint cells rather than the collapsed footprint AABB.

## References
`scripts/actions/construction_action.gd`; `scripts/actions/player_safe_action.gd`.
Related: the untyped positional work-tuple that lets previews/safety/geometry drift onto different cell
sets — see [[actions-untyped-work-tuple]].
