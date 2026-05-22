# Project Status

> **Maintenance contract:** the "Resumption Brief" must reflect the current
> moment. The "Tracker" below it can drift a little. If updating this doc
> after a session takes more than ten minutes, it's too big — shrink it.

---

## Resumption Brief

*Last updated: cleanup pass complete (steps #1, #2, #3, #5, #6, #7+#9, #8
from `docs/code-cleanup-plan.md`; step #4 explicitly deferred to v0.0.1).
v0.0 thesis demo unchanged; pivot is now v0.0.1 (persistence as
replayable history) and playtester binaries.*

**Where you are:** v0.0 thesis demo still works end-to-end — dig a wide
cave, ceiling cells develop a strain gradient, fail to reinforce and
watch a falling RigidBody3D, or place a beam under it and watch
support propagate back up. The cleanup pass restructured the codebase
without semantic change:

- `StructuralIntegrity` is now a `Node` facade composed of three
  `RefCounted` components: `TerrainSupport`, `PartSupport`,
  `IntegrityDebug`. `CollapseDetector` is a peer of `TerrainSupport`,
  not a child of the facade.
- `player.gd` was 339 lines; now 143, composing five helpers
  (`PlayerMovement`, `CameraRig`, `BuildState`, `ActionFactories`,
  `EditModeCatalog`).
- Three dict-as-struct shapes became typed classes (`VoxelRecord`,
  `PendingCollapse`, `PendingFlood`); the inner `PartData` was lifted
  out.
- `FallingBodyFactory` extracted from `CollapseDetector`.
- Design-rationale comments lifted into `docs/architecture.md`; code
  comments aggressively pruned.
- Color-tier ladder data-tabled.
- Support classification cascade extracted into a clean helper
  (`_support_from_neighbor`).

Every file is now under ~200 lines except `edit_mode_catalog.gd` (101 —
the EditMode array builder, hard to shrink without losing
readability). All 5 GUT tests pass. No leak warnings at exit.

**Pick up here:**

1. **Playtest the cleaned v0.0** to confirm the thesis answer hasn't
   shifted. Same demo loop as before; the question of whether voxel-
   first construction-and-integrity is as good an idea as it seemed is
   still up for Robert to decide.

2. **v0.0.1: persistence as replayable history.** Save/load scoped as
   action-journal + periodic snapshot. The Action pattern is in place
   and clean; the work is serialisation, snapshot cadence, schema
   versioning, and determinism discipline. Step #4 (collapse-detector
   state machine) was deferred specifically to land alongside the
   replay harness — together they give regression coverage for the
   subtle phase ordering. See `roadmap.md`.

3. **Playtester binaries.** Linux + macOS + Windows via GitHub
   Actions (cross-compile from a Linux runner with MinGW for Windows,
   native on `macos-latest`). Not yet started. Robert wants v0.0
   locally first to decide it's not embarrassing before distributing.

4. **v0.1 scoping.** When the v0.0 (and v0.0.1) answers come back
   "yes," the v0.1 question is "can I make it fun/performant?" — see
   `roadmap.md` Phases 1, 3, 4, the deferred list below, and the
   "honest physics interaction" design direction.

**Architectural status — what's solid, what's known-imperfect:**

- Structural integrity is the load-bearing thesis claim. Still works.
  Facade composition makes ownership of state explicit and persistence
  surface-area easier to identify.
- Parts are parametric (one-line `.tres` for new shapes), multi-axis
  rotation works, material independently selectable at build time.
- Physics integration: thin parts use `continuous_cd`, fills refuse on
  top of RigidBody3Ds, terrain edits wake sleeping bodies.
- Construction placement snaps `placement_pos.y` to `floor(hit_pos.y)`
  so parts always sit on cell Y-boundaries. Avoids the "click on a
  slope, part floats above the surface" failure mode by anchoring to
  the cell containing the click.
- **Performance is CPU-bound** and observably degrades under heavy
  digging. The debug-cube viz (V toggle) is the biggest contributor
  when on; with it off, framerate is smooth. Threading + MultiMesh
  for debug viz are v0.1 work, documented in roadmap.
- **SDF seam matching** still deferred to v0.1+ under the "honest
  physics interaction" design direction.
- **Intersecting parts do not mutually support each other.** Building
  cross-beams (one beam intersecting another in shared cells) requires
  welding/joining, which is v0.1. Current `ConstructionAction.validate`
  accepts intersection placement so cross-beams can be *placed*, but
  the new beam's support is computed independently — it sees the other
  beam as the supporter only via the "cell below" path, not via shared
  cells.

---

## Tracker

### v0.0 — Phase status

| Phase | State | Notes |
|-------|-------|-------|
| 0 — Foundation | Complete | godot + godot_voxel build chain, walking-around prototype |
| 2 — Terrain Modification | Complete | dig, fill, flatten with refuse-don't-deform |
| 5 — Building System | Functionally complete for v0.0 | Parts, structural integrity, cave integrity, pillar reinforcement all working; SDF seam matching deferred to v0.1+ |
| Cleanup pass | Complete | Plan in `docs/code-cleanup-plan.md`; step #4 deferred to v0.0.1 |

### v0.0.1 — Scope

Full design in `roadmap.md`. Summary: serialise `Action` history as an
append-only journal, periodic state snapshots, versioned save format
with action-schema versioning, deterministic replay (seeded RNG, no
wall-clock reads), debug controls for stepping through history. Not
started. Cleanup step #4 (collapse-detector state machine) folds into
this work — the state machine is easier to test against a deterministic
replay harness than against ad-hoc cave-digging.

### In flight

*(nothing in flight — playtesting cleaned v0.0)*

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

### Deferred to v0.1+ (the "can I make it fun?" question)

| Item | Why deferred |
|------|--------------|
| SDF seam matching (Option A2) | Sub-cell parts can't be represented at 1m voxel resolution; better answered by physics-driven part-vs-terrain interaction |
| Welding / joining (intersecting parts mutually support) | Needs a joint/weld data model; current `_cell_to_part` stack doesn't represent shared structural attachment |
| Load propagation (top-down weight pass) | Pairs with falling damage and SDF-seam-as-physics |
| Falling damage (impact breaks parts, crumbles dirt) | Needs a damage model |
| Hinge-at-boundary collapse | Polish on falling drama |
| Fallen-dirt-as-terrain | RigidBody3D rejoining SDF when at rest |
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
