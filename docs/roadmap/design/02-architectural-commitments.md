# Architectural Commitments

These are decisions that have been made, work as expected, and would
cost more than they save to revisit. Listed here so they're easy to
point at when a refactor proposal forgets one of them.

Mechanism rationale for shipped code lives in `architecture.md`.
Current-state tracking lives in `../../STATUS.md`. This chapter is the
*forward-looking* commitments — what stays true going forward.

## Engine + build chain

- Track Godot 4.6-stable + godot_voxel v1.6. Pinned in
  `tools/versions.env`.
- Double-precision godot_voxel build from day one. Non-retrofittable.
- No engine forks. Pull upstream directly.
- `godot/modules/voxel` symlink, not `custom_modules`.

## Event bus

- Voxel changes flow through `VoxelEventBusSingleton` (autoload).
  Actions emit typed events; structural components subscribe. Mutations
  don't call `StructuralIntegrity` methods directly. Queries
  (`has_part_cell`, etc.) still do — they're synchronous validation, not
  notification.
- Bus subscriptions use WeakRef lifetime. Each subscription stores
  `WeakRef(owner) + method name`. Dead subscribers prune lazily on emit.
  Subscribers can be created and forgotten — no `dispose()` required.
  Caveat: subscribe with `self.method_name`, not anonymous lambdas.
- Every event payload carries `grid_id` even though only one grid
  exists. Multi-grid (Phase 5.5d) lands without payload churn.
- `class_name VoxelEventBusType` on the script; autoload named
  `VoxelEventBusSingleton` (Godot 4 forbids the names from colliding).

## Persistence

- Terrain SDF persists via `VoxelStreamSQLite` (continuous, no manual
  save). Structural state persists via snapshot, gated on
  `is_quiescent()`. Snapshot restore bypasses the propagation queue;
  saved support values are trusted because save required quiescence.
- Snapshot version check is asymmetric: newer-than-known is rejected;
  older loads with missing fields defaulted.

## Structural integrity

- Facade composition: `StructuralIntegrity` (Node) holds three
  `RefCounted` components (`TerrainSupport`, `PartSupport`,
  `IntegrityDebug`) plus `CollapseDetector` (peer of `TerrainSupport`).
  Components hold typed back-references to each other; the facade
  breaks the cycle in `_exit_tree` to let RefCounteds free cleanly.
- Worklist-fixpoint propagation for terrain support. Not generalised
  until a second customer (fatigue/fluid/temperature) appears.
- Per-column bedrock detection (`_lowest_registered_y`) distinguishes
  real bedrock from suspended mass.
- Lazy expansion bounded by material decay: cascade stops where
  support reaches `FALL_THRESHOLD` (~20 cells for STONE).
- Part support recomputed fresh per frame, sorted bottom-up by
  `placement_y`. Per-cell stack of parts (`Array[Node3D]`)
  disambiguated by `placement_y`.
- In-limbo semantics: parts with dirty dependencies don't accumulate
  strain.
- FIFO dirty queue. BFS is the right shape for support propagation.

## Player composition

- `player.gd` (a `CharacterBody3D`) composes five `RefCounted` helpers:
  `PlayerMovement`, `CameraRig`, `BuildState`, `ActionFactories`,
  `ToolCatalog`. Activities organised under tools (None / Landscape /
  Construction); Tab cycles tools, 1-9 picks activity within. Per-tool
  activity memory.
- Helper lambdas inside `ToolCatalog._build_catalog` capture local
  refs, not `self`, to avoid the Node ↔ RefCounted ↔ Callable cycle
  that leaks meshes at exit.
- Shift is reserved as a chord modifier: Shift+key suppresses the
  underlying WASD-bound input. Shift+W is a distinct input from W, not
  "walk + something."

## Actions

- Action-as-data; targeting at the call site. Actions take final
  computed parameters, not raw input.
- Each Action implements `preview() -> ActionPreview` returning the
  cells it would change classified by intent. `VoxelPreviewRenderer`
  (world-space) reads this each frame and draws the cells.
- Refuse-don't-deform: actions refuse via `validate()` when constraints
  can't be met. Extended to physics state via `intersect_shape` for
  additive verbs that might overlap a `RigidBody3D`.

## Data shapes

- Typed records over dict-as-struct: `VoxelRecord`, `PartData`,
  `PendingCollapse`, `PendingFlood`, `ActionPreview` are RefCounted
  classes.
- Typed dicts (`Dictionary[K, V]`) for `part_registry`, `voxel_data`,
  `_voxel_to_pending`. Plain `Dictionary` poisons inferred types from
  iteration.

## Why godot_voxel (and the DC-QEF caveat)

godot_voxel is the single most important dependency. Without it, the
voxel engine alone is 6–12 months. With it you get: chunk-based
infinite terrain with LOD, TransVoxel and blocky meshing, built-in
terrain editing (SDF operations), material/texture support per voxel,
chunk streaming and persistence, multithreaded mesh generation.

MIT licensed, actively maintained, releases tracking Godot stable
branches.

**Tradeoff:** coupling to a third-party module. If Zylann stops
maintaining it, you fork. Acceptable risk for MVP. The module is C++
with clear interfaces — forkable by someone with the right experience
if necessary.

**Use the double-precision build** from the start for planet-scale
future-proofing.

**The DC-QEF transition (see
[`../implementation/done/14-dc-qef-transition.md`](../implementation/done/14-dc-qef-transition.md))
replaces godot_voxel's meshing layer but keeps its storage, streaming,
and LOD.** This is *not* a Hytale-style rewrite — it's surgical
replacement of one layer (~15–20% of what godot_voxel does for us) to
get the geometric representation the thesis requires.
