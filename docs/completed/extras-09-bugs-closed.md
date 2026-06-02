# Completed: Bugs Closed

A running log of named bugs that have been closed. Bugs that surfaced
during a phase and were closed by that phase's work live in the
phase's completed/ entry; this file is for the cross-cutting ones.

## Bug 1 — Fallen chunks not waking

**State:** Closed.
**Fix:** `body.can_sleep = false` on falling rigid bodies.

The first physics-vs-godot quirk. Falling chunks would `sleep` against
the ground and then refuse to wake up if hit. Setting `can_sleep =
false` on the body during its falling lifecycle prevents this; once it
integrates back into terrain (see [fallen-dirt-as-terrain](extras-02-fallen-dirt-as-terrain.md))
the rigid body is freed entirely.

## Bug 2a — Flatten lateral sheet artefact

**State:** Closed by [Phase 5.5b2](implementation-05-phase-5_5b-construction-mode.md).

The pre-5.5b flatten operation cut a single lateral sheet — every cell
in the cut box would lower regardless of whether that column could
*reach* air. Result: floating chunks of terrain over voids the cut
opened up.

Closed by the column-based work computation: each lateral column cuts
up to the reachable air within radius, not a single sheet.

## Bug 2c — Player fall-through on additive edits

**State:** Closed by [Phase 2 action infrastructure](implementation-03-phase-2-terrain-modification.md).

Filling a region the player was standing in (or removing the player's
support cell with flatten) would drop the player through the world.
Originally patched with `_push_player_above_terrain` (scaffolding);
properly fixed in Phase 2 by refusing via `Action.validate()`.

`_push_player_above_terrain` and its `FALLTHROUGH_SEARCH_*` constants
were deleted. **Principled fix; no scaffolding.**

## Phantom-voxel deregistration

**State:** Closed by [tools/activities + console work](extras-06-tools-activities-ui.md)
(`3ebf5cf`).

`TerrainSupport`'s `terrain_sdf_changed` handler registered newly-
exposed cells but didn't deregister cells whose SDF had become air.
Result: phantom strain indicators on cells that no longer existed.

Fix is symmetric with the existing register-on-boundary code:
deregister tracked records whose SDF has become air.
