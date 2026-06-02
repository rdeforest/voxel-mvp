# Completed: Phase 2 — Terrain Modification

Maps to [`../roadmap/implementation/03-phase-2-terrain-modification.md`](../roadmap/implementation/03-phase-2-terrain-modification.md).

## What shipped

Dig, fill, and flatten as the first three terrain verbs, all routed
through the same `Action` infrastructure that later phases reuse.

- `Action` base class: `validate() -> bool`, `execute()`. Conservative
  shape — the discipline is the routing, not the size of the base
  class.
- `DigAction`, `FillAction`, `FlattenAction` as the initial three
  concrete actions.
- `EditMode.execute` renamed to `make_action`. It now *produces* an
  Action rather than modifying the world directly.
- Player's `_try_edit_terrain` collapsed to six lines: get hit, call
  `make_action`, validate, execute.
- godot_voxel built-in chunk save/load for terrain modification
  persistence.

## Key decisions taken

- **Action-as-data adopted as foundational pattern.** Every world-
  modifying operation routes through `Action`. This is the architectural
  commitment that later enables the event bus, the preview-as-data
  refactor, and the eventual op-log replication in the network design.
- **Refuse-don't-deform.** Actions refuse via `validate()` when
  constraints can't be met, rather than scaffolding around bad inputs.
  The shipped example: `FillAction.validate()` refuses when the player
  is within `radius + PLAYER_CLEARANCE`; `FlattenAction.validate()`
  refuses when the player is on the fill side of the plane within
  lateral radius. Bug 2c (player fall-through) was rerouted through
  `validate()` and `_push_player_above_terrain` + its
  `FALLTHROUGH_SEARCH_*` constants were deleted. **Principled fix; no
  scaffolding.**

## Lessons learned

- **The scaffolding patch tells you where the design goes.** The
  earlier `_push_player_above_terrain` was a working fix for fall-
  through, but its existence was a signal: additive edits can place
  voxels where the player is, and that's a class of problem that wants
  a structural answer. The `AdditiveAction` taxonomy in Phase 5.5b1
  is the structural answer.
- **Action-as-data was a bigger commitment than it looked.** At the
  time it seemed like "the boring refactor"; in retrospect it was the
  single biggest architectural decision of v0.0. It enables the event
  bus, the preview-as-data work, and the eventual op-log replication.
  When in doubt, route through an Action.

## Deferred (with reasons)

- **Particle effects on terrain edit (dust, debris).** Deferred to
  v0.2 art pass. Programmer art is fine here; VFX needs an art pass to
  not look worse than no VFX.

## Validation

Tunnel into a hillside, carve out a room, build a mound, cut a sheer
vertical face. All work. Player no longer falls through the world
during fill operations.
