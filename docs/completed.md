# Completed work

## Bugs

| ID | Notes |
|----|-------|
| 1 | Fallen chunks not waking — fixed (`body.can_sleep = false`) |

## v0.0 cycle

- **Phases 0 and 2 complete.** Procedural terrain, FPS controller, gravity,
  day/night (Phase 0). Dig/fill/flatten routed through Action infrastructure
  (Phase 2).
- **Phase 5 design pass.** Hybrid voxel + prefab using matching-SDF-shell
  technique (Option A2). Axis-aligned cell footprints, 90° rotation only.
  Refuse-don't-deform principle for placements that can't satisfy
  constraints. Mid-break destruction deferred (whole-prefab destruction
  only for Phase 5). In-game editor deferred to v0.9+; mocked prefabs by
  hand. Non-adjacent linkages (cables, ropes) deferred. Performance
  Fermi-estimated: 36× headroom on worst case; press on.
- **Object terminology committed.** **Part** (board, beam, sheet), **Assembly**
  (door, wagon — composed of Parts and sub-Assemblies, may have Behaviors),
  **Mold** (captured SDF region for terrain stamping) — all are kinds of
  **Schematic**. A **Construction** **Action** instantiates a Schematic as a
  **Placement** in the world. Placements connect via **Joints**. Schematics
  can have **Behaviors**. **Sites** are regions with metadata (deferred).
- **Action-as-data adopted as foundational pattern.** Every world-modifying
  operation routes through `Action`. Conservative implementation (one
  `validate()`, one `execute()`); architectural commitment is the discipline
  of routing, not the size of the base class.
- **Action infrastructure built.** `Action` base class (`validate()` returns
  bool, `execute()` does the work). `DigAction`, `FillAction`, `FlattenAction`
  refactored from inline player methods. `EditMode.execute` callable renamed
  to `make_action`; it now produces an Action rather than modifying the world
  directly. Player's `_try_edit_terrain` is six lines: get hit, call
  `make_action`, validate, execute.
- **Bug 2c rerouted through `validate()`.** `_push_player_above_terrain` and
  its `FALLTHROUGH_SEARCH_*` constants deleted. `FillAction.validate()`
  refuses when the player is within `radius + PLAYER_CLEARANCE`.
  `FlattenAction.validate()` refuses when the player is on the fill side
  of the plane within lateral radius. Principled fix; no scaffolding.
