# Completed: Cleanup Pass

**Commits:** `704af67`, `78c398e`, `43e0d9c`, `e00513b`

## What shipped

Between v0.0 demo and Phase 5.5a, a deliberate cleanup pass refactored
the v0.0 code from "thesis-defending" into "v0.1-extendable."

- **Typed records.** `VoxelRecord`, `PartData`, `PendingCollapse`,
  `PendingFlood`, `ActionPreview` as RefCounted classes. Replaced
  dict-as-struct usage that was poisoning inferred types from
  iteration.
- **Facade + components split.** `StructuralIntegrity` (Node) now
  holds three RefCounted components (`TerrainSupport`, `PartSupport`,
  `IntegrityDebug`) plus `CollapseDetector` as a peer of
  `TerrainSupport`. Components hold typed back-references to each
  other; the facade breaks the cycle in `_exit_tree` to let
  RefCounteds free cleanly.
- **Player composition.** `player.gd` (a `CharacterBody3D`) composes
  five RefCounted helpers: `PlayerMovement`, `CameraRig`, `BuildState`,
  `ActionFactories`, `ToolCatalog`. Each helper has a single
  responsibility; `player.gd` is now a coordinator, not an
  implementation.
- **Support classification cascade** — the three-state classification
  for falling bodies (free / partial-buried / full-buried) was
  refactored into a clean state machine.
- **Comment pruning** — comments that restated what the code obviously
  did were removed. Comments now explain *why*, not *what*.
- **`docs/architecture.md` created** — mechanism rationale for the
  shipped code in one place.
- **Materials → `.tres` refactor (`e00513b`).** Material definitions
  moved out of code into Godot `.tres` resources. Modding-friendly
  from day one; matches the data-driven principle that v0.9 inventory
  + crafting will lean on.

## Key decisions taken

- **Typed records over typed dicts.** Both work; typed records compose
  better with GDScript's inferencer. The dict-as-struct pattern was
  poisoning inferred types from iteration in enough places that
  switching to RefCounted classes paid for itself.
- **Facade-with-components, not god-object.** `StructuralIntegrity`
  was approaching the size where understanding any one piece required
  understanding the whole. Splitting into TerrainSupport / PartSupport
  / IntegrityDebug / CollapseDetector lets each piece be reasoned
  about independently.
- **Helper lambdas inside `ToolCatalog._build_catalog` capture local
  refs, not `self`.** This avoids the Node ↔ RefCounted ↔ Callable
  cycle that was leaking meshes at exit. Caught during the cleanup.
- **`Dictionary[K, V]` typed dicts** for `part_registry`, `voxel_data`,
  `_voxel_to_pending`. Plain `Dictionary` was poisoning inferred types
  from iteration; the typed annotation propagates cleanly.

## Lessons learned

- **The cleanup pass surfaced multiple latent bugs.** The
  ToolCatalog lambda-self-capture cycle wasn't causing visible
  problems yet but would have surfaced as memory growth across
  long sessions. Cleanup found it. Pattern: **cleanup is also a
  bug-finding exercise.**
- **`architecture.md` was overdue.** Once written, every "wait, why
  does this work this way?" question had a single place to look.
  Mechanism rationale for shipped code is a permanent doc; design
  rationale for forward-looking work belongs in the roadmap.
- **Step #4 of the cleanup plan was deferred.** The
  collapse-detector state machine cleanup was held until a v0.0.1
  replay harness exists, so regressions are catchable. Right call —
  refactoring state machines without replay is asking for silent
  breakage.

## Deferred

- **Cleanup step #4: collapse-detector state machine.** Pending the
  action-journal/replay harness. → FEAT045.
