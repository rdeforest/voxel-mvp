# Project Status

> **Maintenance contract:** the "Resumption Brief" must reflect the current
> moment. The "Tracker" below it can drift a little. If updating this doc
> after a session takes more than ten minutes, it's too big — shrink it.

---

## Resumption Brief

*Last updated: Phase 5.5a (event bus), 5.5b1+b2 (AdditiveAction +
honest-failure flatten), and fallen-dirt-as-terrain are all landed.
A voxel grid overlay (G key) helps the player see voxel boundaries.
Next: 5.5b3 (preview UI) or new verbs (Raise/Lower/FillVoxel/
EmptyVoxel).*

**Where you are:** v0.0 demo + persistence + bus + honest flatten +
falling-debris-integrates-with-terrain all working. Recent landings:

- **Phase 5.5b1+b2** (commit `15308bd`). `AdditiveAction` base class
  declares the bury-relevant verbs (Fill/Flatten/Construction).
  `FlattenAction` rewritten with column-based work computation:
  cells in the cut box are bucketed by their lateral projection onto
  the plane; each column's +N side cuts only if it reaches existing
  air within radius, -N side fills only if it reaches existing solid
  within radius. Refuses silently if no column has work. Box is now
  symmetric around the plane point. Per-cell player-endanger check
  catches "you'd cut my support" before "you'd bury me," fixing
  the slope-fall-through case.

- **Fallen-dirt-as-terrain** (this session). Falling rigid bodies
  now classify themselves each physics tick by sampling SDF at each
  of their original cells' current world positions. Three outcomes:
  free (default — sleeps when at rest), partially buried (`freeze =
  true` to lock in place; reclassifies each tick so a later dig
  un-freezes them), fully buried (emit `voxel_added` per cell, free
  the body). `FillAction` freezes overlapping bodies *before* the
  SDF mutation lands so physics doesn't squirt them sideways. The
  RigidBody3D refusal in `FillAction.validate` is gone — fills into
  bodies are now valid, the burial system handles the integration.

- **Voxel grid overlay** (this session). G toggles a wireframe
  display of the targeted cell and its Chebyshev neighborhood (3
  shells out, 7³ = 343 cubes), drawn via ImmediateMesh.

19/19 GUT tests pass.

**Pick up here:**

1. **5.5b3 — preview UI.** Communicate flatten intent visually
   (which cells will cut, which fill, refuse state). Currently
   refusals are silent.

2. **New verbs (Robert's request).** RaiseAction / LowerAction
   (flatten-like but bell-shaped), FillVoxelAction / EmptyVoxelAction
   (per-voxel surgical control). Greatly expand creative options.

3. **Playtester binaries.** Linux + macOS + Windows via GitHub
   Actions. Not yet started.

4. **v0.1 gameplay scoping.** When 5.5b3 is done, the v0.1 question
   is "can I make it fun/performant?" — see `roadmap.md` Phases 1,
   3, 4.

**Architectural status — what's solid, what's known-imperfect:**

- Structural integrity is the load-bearing thesis claim. Still works.
  Facade composition + bus decoupling means adding a second indexer
  (building registry, biome map, etc.) is a `subscribe()` call, not
  a refactor.
- Parts are parametric (one-line `.tres` for new shapes), multi-axis
  rotation works, material independently selectable at build time.
- Physics integration: thin parts use `continuous_cd`, fills refuse on
  top of RigidBody3Ds, terrain edits wake sleeping bodies via
  bus subscription.
- Persistence works: build a structure, F5, F9, structure comes back
  with correct support. Restore-with-saved-support skips the
  propagation race against lazy SDF streaming.
- Construction placement snaps `placement_pos.y` to `floor(hit_pos.y)`
  so parts always sit on cell Y-boundaries.
- **Performance is CPU-bound** and observably degrades under heavy
  digging. The debug-cube viz (V toggle) is the biggest contributor
  when on; with it off, framerate is smooth. Threading + MultiMesh
  for debug viz are v0.1 work.
- **SDF seam matching** still deferred to v0.1+ under the "honest
  physics interaction" design direction.
- **Intersecting parts do not mutually support each other.** Cross-beam
  placement is accepted by `ConstructionAction.validate`, but the new
  beam only sees support through "cell below," not shared cells.
  Welding/joining is v0.1.
- **No performance baseline captured before the bus refactor.** Heavy
  digging *feels* slightly faster post-refactor but wasn't measured.
  A small instrumentation pass (Time.get_ticks_usec deltas on
  action.execute) is cheap insurance for the next refactor.

---

## Tracker

### v0.0 — Phase status

| Phase | State | Notes |
|-------|-------|-------|
| 0 — Foundation | Complete | godot + godot_voxel build chain, walking-around prototype |
| 2 — Terrain Modification | Complete | dig, fill, flatten with refuse-don't-deform |
| 5 — Building System | Functionally complete for v0.0 | Parts, structural integrity, cave integrity, pillar reinforcement all working; SDF seam matching deferred to v0.1+ |
| Cleanup pass | Complete | Plan in `docs/code-cleanup-plan.md`; step #4 deferred |
| Persistence (snapshot + stream) | Complete (`a4b95da`) | F5 save, F9 load, terrain SDF auto-persists. Action-journal/replay deferred. |

### v0.1 — Phase status

| Phase | State | Notes |
|-------|-------|-------|
| 5.5a — Voxel event bus | Complete (`ee80b63`) | Autoload bus, typed events, WeakRef lifetime |
| 5.5b1 — AdditiveAction base | Complete (`15308bd`) | Verb classification, shared PLAYER_CLEARANCE |
| 5.5b2 — Honest flatten | Complete (`15308bd`) | Column-based work, symmetric box, per-cell endanger check |
| 5.5b3 — Preview UI for honest verbs | Not started | Next architectural item |
| 5.5c — Fracture as mesh extraction | Deferred to v0.2 | per roadmap |
| 5.5d — Multi-grid foundation | Deferred to v0.2/v0.9 | grid_id carried in payloads from day one |
| 5.5e — Per-channel non-SDF data | Deferred to v0.2/v0.9 | |
| Fallen-dirt-as-terrain | Complete (this session) | Falling bodies freeze on partial bury, integrate as tracked SDF on full bury |

### In flight

*(nothing in flight — Phase 5.5b is the next scheduled work)*

### Bugs

| ID | State | Notes |
|----|-------|-------|
| 2c | Closed | Player fall-through fixed via `Action.validate()` refusal |
| 2a | Deferred | Flatten clears only one sheet above — cosmetic; deferred until building system replaces flatten |

### Architectural commitments worth not re-litigating

- **Track Godot 4.6-stable + godot_voxel v1.6.** Pinned in `tools/versions.env`.
- **Double-precision godot_voxel build from day one.** Non-retrofittable.
- **No engine forks.** Pull upstream directly.
- **`godot/modules/voxel` symlink, not `custom_modules`.**
- **Voxel changes flow through `VoxelEventBus` (autoload).** Actions
  emit typed events; structural components subscribe. Mutations don't
  call `StructuralIntegrity` methods directly. Queries
  (`has_part_cell`, etc.) still do — they're synchronous validation.
- **Bus subscriptions use WeakRef lifetime.** Each subscription stores
  `WeakRef(owner) + method name`. Dead subscribers prune lazily on
  emit. Subscribers can be created and forgotten — no `dispose()`
  required. Caveat: subscribe with `self.method_name`, not lambdas.
- **Every event payload carries `grid_id`** even though only one grid
  exists. Multi-grid (Phase 5.5d) lands without payload churn.
- **Terrain SDF persists via `VoxelStreamSQLite`** (continuous, no
  manual save). Structural state persists via snapshot, gated on
  `is_quiescent()`. Snapshot restore bypasses the propagation queue;
  saved support values are trusted because save required quiescence.
- **Facade composition for `StructuralIntegrity`.** A `Node` facade
  holds three `RefCounted` components (`TerrainSupport`, `PartSupport`,
  `IntegrityDebug`) plus `CollapseDetector` (peer of `TerrainSupport`).
  Components hold typed back-references to each other; the facade
  breaks the cycle in `_exit_tree` to let RefCounteds free cleanly.
- **Player composes RefCounted helpers.** Movement, camera, build
  state, action factories, edit-mode catalog — each owns one concern.
  Helper lambdas capture local refs, not `self`, to avoid the
  Node ↔ RefCounted ↔ Callable cycle that leaks meshes at exit.
- **Typed records over dict-as-struct.** `VoxelRecord`, `PartData`,
  `PendingCollapse`, `PendingFlood` are RefCounted classes. Field
  access replaces string-keyed dict lookups; iteration variables type
  correctly.
- **Worklist-fixpoint propagation for terrain support.** Not generalised
  until a second customer (fatigue/fluid/temperature) appears.
- **Per-column bedrock detection (`_lowest_registered_y`).** Distinguishes
  real bedrock from suspended mass.
- **Lazy expansion bounded by material decay.** Cascade stops where
  support reaches `FALL_THRESHOLD`; for STONE that's ~20 cells per
  chain.
- **Part support recomputed fresh per frame, sorted bottom-up by `placement_y`.**
- **Per-cell *stack* of parts (`Array[Node3D]`).** Disambiguated by
  `placement_y`.
- **In-limbo semantics.** Parts with dirty dependencies don't
  accumulate strain.
- **Action-as-data; targeting at the call site.** Actions take final
  computed parameters, not raw input.
- **Refuse-don't-deform extended to physics state.** FillAction refuses
  on top of RigidBody3D via `intersect_shape`.
- **Construction placement Y snaps to `floor(hit_pos.y)`.** Parts
  always sit on cell Y-boundaries.
- **FIFO dirty queue.** BFS is the right shape for support propagation.

### Done this v0.0 cycle

Listed roughly in chronological order. Detailed rationale and earlier
items in git history; commit hashes in parentheses where useful.

- Action infrastructure (`scripts/actions/`), refuse-don't-deform principle.
- Part/Schematic resource hierarchy, parametric dimensions, procedural build.
- Part-level structural integrity, per-cell stack semantics, direct-supporter
  selection, material decay propagation.
- Multi-axis 90° rotation, AABB-driven instance shift.
- Strain visualisation: emission tracking support color, hover tint,
  in-limbo pause.
- Falling-part physics: `continuous_cd`, sleep-wake on terrain change,
  fill-refuses-on-RigidBody3D.
- Cave integrity: dig-time registration of exposed cells.
- Lazy-expansion model with per-column bedrock detection.
- Register-part dirties terrain neighbours.
- Material override at construction time (M key cycles).
- Debug-cube toggle wired to V key.
- README + LICENSE + dependency-licensing notes.
- Materials → `.tres` refactor (e00513b).
- **Cleanup pass** (704af67, 78c398e, then the `cleanup/player-split`
  fast-forward and `43e0d9c`):
    - Typed records (`VoxelRecord`, `PartData`, `PendingCollapse`,
      `PendingFlood`).
    - `FallingBodyFactory` extracted.
    - Comment pruning + `docs/architecture.md` created.
    - `StructuralIntegrity` split into facade + 3 components.
    - `get_support_color` color-tier table.
    - `player.gd` split into 5 helpers.
    - Support classification cascade extracted.
    - Construction placement snaps Y to cell boundary.
    - `ConstructionAction.validate` accepts intersection placement.
- **Persistence** (`a4b95da`): `VoxelStreamSQLite` for terrain;
  `WorldSnapshot` (var_to_str) for structural + player state. F5 save
  (quiescence-gated), F9 reload-scene. `TerrainSupport.restore_voxel`
  bypasses dirty queue using saved support values.
- **Phase 5.5a — voxel event bus** (`ee80b63`): autoload
  `VoxelEventBus` with per-cell + channel-wide subscriptions, typed
  event classes (`scripts/events/`), WeakRef lifetime. Actions emit
  primitives; integrity components emit derived events. The old
  `voxel_support_increased` signal and `register_voxel`/`remove_voxel`/
  `notify_terrain_changed`/`register_exposed_cells`/`register_part`/
  `remove_part` facade methods are all gone.
- **Phase 5.5b1+b2** (`15308bd`): `AdditiveAction` base for verbs that
  can bury the player. `FlattenAction` rewritten with column-based
  work computation (bucket cells by lateral plane projection; each
  column's side cuts only if it reaches existing air-or-solid within
  radius). Symmetric box around `plane_point`. Per-work-cell
  endanger check catches both "fill into player capsule" and "remove
  player's support cell."
- **Fallen-dirt-as-terrain** (this session). Falling rigid bodies
  carry `cell_offsets` metadata. `StructuralIntegrity._tick_falling_
  bodies` reclassifies them each physics tick: fully buried →
  emit `voxel_added` per cell and free; partial → `freeze = true`;
  un-buried (was frozen but no longer touches solid SDF) → unfreeze.
  `FillAction` freezes overlapping bodies before mutating SDF so
  they don't squirt.
- **Voxel grid overlay** (this session). `scenes/player/voxel_grid_
  overlay.gd`. G toggles a wireframe MeshInstance3D drawn via
  ImmediateMesh. 4 Chebyshev shells from the targeted cell, alphas
  0.9 / 0.6 / 0.3 / 0.1. Helps the player understand voxel boundaries
  during fill/flatten/dig.

### Deferred to v0.1+ (the "can I make it fun?" question)

| Item | Why deferred |
|------|--------------|
| SDF seam matching (Option A2) | Sub-cell parts can't be represented at 1m voxel resolution; better answered by physics-driven part-vs-terrain interaction |
| Welding / joining (intersecting parts mutually support) | Needs a joint/weld data model; current `_cell_to_part` stack doesn't represent shared structural attachment |
| Load propagation (top-down weight pass) | Pairs with falling damage and SDF-seam-as-physics |
| Falling damage (impact breaks parts, crumbles dirt) | Needs a damage model |
| Hinge-at-boundary collapse | Polish on falling drama |
| RaiseAction / LowerAction (bell-shape) | Robert-requested; "after we're done with 5.5" |
| FillVoxelAction / EmptyVoxelAction (per-voxel) | Robert-requested; per-voxel surgical control |
| Sub-assemblies + planning mode (Dwarf-Fortress queue) | Significant UI work |
| Free-form placement with physics settle-to-construction | Architectural change; current grid-aligned demo carries thesis |
| Snap point authoring UI | Data structure exists; UI is v0.1 |
| Specialised joinery pieces (doors, stairs, mating constraints) | Rectangular parts demonstrate the system |
| Terrain strain on mesh surface (replace debug cubes with MultiMesh + update-on-change) | Real shader work; current per-frame per-cube material poke is the framerate cost |
| Highlight parts depending on about-to-fall things | Dependency-graph walk |
| Budget-consumption telemetry | Dynamic budget adjustment depends on this |
| Player-controlled dig/fill shapes & sizes | UX polish |
| KSP-style parametric Part dimensions in-game | Tooling polish |
| Per-material strain duration; nature-of-change reset scaling | Tuning pass |
| Gap-between-layered-parts | Needs `PartData.dimensions` |
| Mid-break Part destruction | Whole-part destruction is enough for v0.0 |
| Non-adjacent linkages (ropes, cables) | New data structure required |
| Material fatigue (cumulative strain history) | Only meaningful with mobs (v0.9) |
| In-game Schematic editor | Hand-authored `.tres` is fine; v0.9+ |
| Workbench radius | Valheim survival-loop mechanic; v0.9+ if at all |
| Cross-platform binary builds | Release plumbing; GitHub Actions pattern |
| Collapse-detector state machine (cleanup step #4) | Defer until v0.0.1 replay harness exists, for catchable regressions |

### Known limits (recorded, not fixed)

- **Flatten preview Z-fights with the surface it's matching.** Cosmetic;
  cleanest fix is a small forward offset on the preview plane normal.
- **`_resume_unfinished_floods` budget starvation:** components larger
  than `DETECTION_BUDGET` (500 voxels) take multiple settled frames to
  fully detect.
- **`PLAYER_CLEARANCE = 1.0m`** in Fill/Flatten is a guess.
- **Lazy-expansion cascade per dig is bounded by material decay budget.**
  For STONE (decay 0.05), the cascade reaches ~20 cells. Future
  load-propagation will need its own cascade rules.
- **`_recompute_column_low` scans `voxel_data`.** Fast for ~10k tracked
  cells; replace with per-column ordered set if tracked count grows.
- **Cross-beam placement validates but doesn't mutually support.**
  Placing one beam through another succeeds (intersection is a valid
  attachment per `validate`), but the new beam only sees support
  through "cell below," not through shared cells. Welding/joining is
  v0.1.
- **Debug-cube viz is the dominant framerate cost** when enabled.
  Per-frame iteration over every tracked voxel + per-cube material
  poke. `V` toggles it off; v0.1 should rewrite on MultiMesh and only
  update on change.

---

## How to update this doc

After each session:

1. Rewrite the **Resumption Brief** completely. It must reflect *right
   now*, not history. If you find yourself adding to it instead of
   replacing, the item probably belongs in the Tracker.
2. Move "in progress" items in the Tracker to "Done this v0.0 cycle"
   as they finish. Add new entries to Deferred / Known Limits as they
   emerge.
3. If the Tracker is hard to navigate, it's too big. Move older "Done"
   entries into a one-line summary like "Phase X complete (commit
   abc123)" and trust git for the detail.
4. If updating this doc took more than ten minutes, something is
   wrong with its shape.
