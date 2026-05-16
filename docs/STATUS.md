# Project Status

> **Maintenance contract:** the "Resumption Brief" must reflect the current
> moment. The "Tracker" below it can drift a little. If updating this doc
> after a session takes more than ten minutes, it's too big — shrink it.

---

## Resumption Brief

*Last updated: end of Phase 5 design + Action infrastructure session*

**Where you are:** v0.0 checkpoint, opening of Phase 5 proper. Phase 5's
design pass is done; the Action infrastructure has been introduced and the
existing terrain edits (dig, fill, flatten) refactored to route through it.
Bug 2c is being retired as a special case of `Action.validate()` refusal
rather than the old march-from-below scaffolding. The actual building system
— Parts, Assemblies, Constructions, placement UI, voxel-to-prefab seam — is
unstarted but fully specified.

**Pick up here, in this order:**

1. **Apply and test the Action refactor.** Six files changed: `action.gd`
   (new), `dig_action.gd` (new), `fill_action.gd` (new), `flatten_action.gd`
   (new), `edit_mode.gd` (`execute` → `make_action`), `player.gd` (uses
   Actions; `_push_player_above_terrain` and its constants deleted). Test
   bug 2c is dead via `validate()` refusal — see test plan below. If
   `PLAYER_CLEARANCE` (1.0m) misbehaves, tune it; it was a guess against
   the unknown CapsuleShape3D dimensions.

2. **Move Phase 5 implementation to Claude Code.** This conversation
   established the design and the Action pattern. The Phase 5 body
   (Schematic resources, first Part, Construction action, placement UI,
   matching-SDF-shell seam handling) will touch many files coherently and
   wants Claude Code's repo-resident workflow rather than file-paste cycles.

3. **First Phase 5 implementation milestone:** the wooden board Part.
   Authored as a `.tres` Schematic with optional `.tscn`, axis-aligned,
   90° rotation only. Bottom-center anchor by default. Construction action
   instantiates it; the Action infrastructure already routes the placement
   through `validate()`/`execute()`. No snap points yet (data structure
   present, UI deferred).

**Active mental state to preserve:** The thesis of Phase 5 is that prefab
pieces and SDF terrain are *one* data structure with two rendering paths.
The seam between them is solved by prefabs writing matching SDF samples
into the cells they occupy (Option A2 — see Phase 5 design decisions).
Costs are paid at edit time, not per-frame. The architecture has 36×
headroom on the structural integrity Fermi estimate; performance is *not*
the worry. Getting the seam visually clean and getting the data model
right are the worries.

---

## Tracker

### v0.0 — Phase status

| Phase | State | Notes |
|-------|-------|-------|
| 0 — Foundation | Done | Procedural terrain, FPS controller, gravity, day/night |
| 2 — Terrain Modification | Done | Dig/fill/flatten now routed through Action infrastructure |
| 5 — Building System | Design done, implementation starting | Structural integrity + strain window done; Action infrastructure done; Schematic/Part/Construction unstarted |

### Bugs

| ID | State | Notes |
|----|-------|-------|
| 1 | Done | Fallen chunks not waking — fixed (`body.can_sleep = false`) |
| 2c | **Test pending** | Player fall-through after fill/flatten — replaced march-from-below scaffolding with `Action.validate()` refusal. Test the refactor (below) before closing. |
| 2a | Deferred | Flatten clears only one sheet above — cosmetic; left until building system replaces flatten |

### Done this v0.0 cycle (latest session)

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

### Phase 5 design decisions worth not re-litigating

- **Hybrid prefab approach (Option A2).** Prefabs occupy voxel cells via
  metadata; they write matching SDF samples into their cells so the
  Transvoxel mesher produces a clean surface continuous with surrounding
  terrain, while the prefab's static mesh renders the engineered geometry.
  Costs are paid at placement / chunk-remesh time, not per-frame.
- **Axis-aligned footprints, 90° rotation.** Rotated prefabs are a v0.9+
  problem; the axis-aligned restriction keeps SDF-matching tractable.
- **Refuse-don't-deform.** Both terrain ops and prefab placements refuse
  when constraints can't be satisfied, rather than silently adjusting.
  Pairs with the existing "fail honest" terrain principle in the roadmap.
- **Action-as-data.** Every world-modifying op routes through `Action`.
  Unlocks undo/redo, macros, replay, multiplayer netcode (lockstep
  simulation), templates, and history. Conservative implementation now;
  architectural commitment from day one.
- **Conservative on shape, conservative on execution.** Per recent
  preference: don't pre-build fields for future needs; refactor when needs
  bite. The Action class stays minimal until a second customer demands
  expansion.
- **Targeting lives at the call site (the EditMode `make_action` callable),
  not inside the Action.** Actions take final, computed parameters. When
  multiple call sites duplicate targeting logic, extract a `Targeting`
  object then; not before.
- **Schematic format: `.tres` resource, optional `.tscn` for scene-graph
  content.** Editor-friendly, serializable, diff-able.
- **Cell footprint authoring: computed from mesh bounds by default, with
  optional hand-override.** The override is rare.
- **Anchor convention: bottom-center of the footprint bounding box by
  default, with optional per-Schematic override.**
- **Snap points are per-Schematic metadata, hand-authored.** Match-time
  Joint creation is a v0.1 follow-on; data structure present, UI deferred.

### Deferred but tracked

| Item | Where it goes | Why deferred |
|------|---------------|--------------|
| Per-material strain duration (`STRAIN_DURATION_SEC` reads from `Materials`) | v0.1 polish / material work | Flat 3.0s is fine for v0.0; the hook is a v0.1 tuning pass |
| Nature-of-change reset scaling (critical pillar buys more time than cardboard prop) | v0.1 polish | Same reasoning; flat `STRAIN_RESET_SEC = 2.7` works |
| Surface-geometry pulse (strain feedback on terrain mesh, not debug cubes) | v0.2 art / shader pass | Real shader work; not v0.0-essential |
| Material fatigue (cumulative strain history → weak points → repair tools) | v0.9 survival/combat | Only meaningful once mobs exist to exploit weak points |
| Respawn anchor system | Deferred, unscheduled | The "right" fix for fall-through; `Action.validate()` refusal covers known cases now |
| Continuous per-tick fall-through check | Deferred | More robust than edit-driven, but interacts oddly with intentionally-enclosed building spaces — revisit when building exists |
| Hinge-at-boundary collapse (undermined towers tip rather than lift off) | v0.1 polish | Materialization refinement; wait for real Phase-5 scenarios to tune against |
| Generic `Propagator` extraction (worklist mechanism separated from policy) | When second use case appears | Fatigue/fluid/temperature could share it; one customer isn't enough to generalize |
| Mid-break prefab destruction (a board snaps in two; each half is a new prefab with custom geometry) | v0.1 polish | Whole-prefab destruction works for Phase 5; mid-break is the complexity bomb (see roadmap discussion) |
| Non-adjacent linkages (ropes, cables, chains; Poly-Bridge tensioning) | Late Phase 5 or v0.1 | Adjacency-based support propagation is free; cross-space linkages need a new data structure |
| Load propagation (top-down pass paired with support; enables Poly Bridge load testing) | v0.1 | Same algorithm as support propagation in reverse; revisit Fermi estimate when added |
| Per-material failure propagation speed (wood snaps fast, stone groans slow) | v0.1 polish | Currently a flat propagation budget; per-material tuning is a parameter pass |
| In-game Schematic editor ("the game is the editor") | v0.9+ | Author Schematics by hand for Phase 5; the rich KSP-level editor is post-MVP |
| Gradual construction (ghosts that manifest over time, possibly with NPC builders) | v0.1+ | Phase 5 places Schematics instantaneously; the Action class can absorb child actions + duration when needed |
| Behaviors as composable units (pumps, water wheels, valves, axles, gears) | v0.9+ | Phase 5 hard-codes Behaviors into Assembly templates; player-composable Behaviors come with the editor |
| Thermal/fire simulation (combustion, smithing, metal sag under heat, black-body radiation) | v0.2+ | Same propagation shape as structural integrity; multiplies gameplay surface dramatically. Material system should anticipate the property fields (`specific_heat`, `thermal_conductivity`, `ignition_temperature`, `combustion_rate`) |
| Reason mechanism on `validate()` (return string/enum, not just bool) | When two callers need different feedback | One caller, one bool, until that changes |
| `WorldContext` parameter object (bundle `terrain`, `integrity`, `player` for Action constructors) | When 5+ Actions all take the same world refs | Verbose-but-explicit constructor parameters until then |
| Sites (regions with metadata: ownership, name, history) | v0.9+ | Needed for ownership, named places, and the history feature; not Phase 5 |
| History/lineage tracking on Placements ("this beam is from the Great Hall…") | v0.9+ | Falls out of action-replay infrastructure once Sites exist |

### Known limits (recorded, not fixed)

- **`_resume_unfinished_floods` budget starvation:** components larger than
  `DETECTION_BUDGET` (500 voxels) take multiple settled frames to fully
  detect; continuous edit streams can starve phase-1 entirely. Not a
  correctness bug, just lag. Comment in `collapse_detector.gd`. Fix is
  budget profiling, deferred to v0.1.
- **VS Code `godot-tools` rejects `bin/godot`:** the extension validates
  its editor path as a binary and chokes on a bash wrapper. Currently
  worked around by pointing it at the real binary directly, which loses
  cross-platform portability of `.vscode/settings.json`. Plausible fix:
  have `tools/build` also emit a per-machine `.vscode/settings.json`. Not
  blocking.
- **`PLAYER_CLEARANCE` in Fill/Flatten actions is a guess (1.0m).** Tuned
  against an unknown CapsuleShape3D height. If refusals fire too eagerly
  (legitimate fills nearby refused) or fall-through reappears (clearance
  too small), tune; may want to derive from the actual capsule dimensions.
- **`FlattenAction` preserves a center/plane-point asymmetry from the
  original `_edit_flatten`:** the bounding box is offset inward from the
  surface but the plane equation runs through the surface hit point. Both
  are explicit constructor parameters now, with a comment. If this turns
  out to be a latent bug, it's easy to change.

### Architectural decisions worth not re-litigating

- **Track Godot stable, not master.** Pin to `4.6-stable` (`89cea1439`).
- **Double-precision godot_voxel build from day one.** The one
  non-retrofittable architectural decision in the roadmap.
- **No engine forks.** Pull upstream directly from `godotengine/godot` and
  `Zylann/godot_voxel`. Fork when there's a concrete patch to write, not
  before.
- **`godot/modules/voxel` symlink, not `custom_modules`.** godot_voxel's
  module folder must be named exactly `voxel`; `custom_modules` derives
  the name from the directory and breaks the registration symbols.
- **Worklist-fixpoint propagation is one customer, not generalized.**
  Don't extract `Propagator` until fatigue/fluid/temperature give it a
  second customer.
- **Signals (not a custom event bus) for `voxel_support_increased`.**
  Direct emitter→listener connection; bus when a third unrelated system
  needs to listen.
- **Strain timer is per-component, accumulated against physics `delta`.**
  Not wall-clock (`Time.get_ticks_msec()` would expire windows during
  pause); not a global clock (the per-component state is the right shape
  for fatigue and per-material rates later).
- **Action-as-data (new this session).** Every world-modifying operation
  routes through `Action`. Conservative implementation; architectural
  commitment from day one.

---

## Bug 2c test plan (do this first)

After applying the Action refactor:

1. **Fill next to player at floor level.** Stand on flat ground, point at
   the ground just to your side, hit Fill. Expected: refused (nothing
   visibly happens). Previously: dropped you through the world.
2. **Fill just above player feet.** Stand on flat ground, point at a spot
   just above your feet, hit Fill. Expected: refused.
3. **Fill far from player.** Stand 10m away from target, hit Fill. Expected:
   works as before.
4. **Flatten the floor you stand on, horizontal mode.** Stand on a mound,
   hold Shift, point at the surface under you, hit Flatten. Expected:
   refused (would remove your footing).
5. **Flatten a wall vertical mode.** Walk up to a hill, hold Ctrl, point
   at the slope, hit Flatten. Expected: works (you're not in the fill
   region).
6. **Dig anywhere.** Expected: always works; no validation on Dig.

If refusals fire too eagerly, decrease `PLAYER_CLEARANCE` in
`fill_action.gd` and `flatten_action.gd`. If fall-throughs persist,
increase it. Reasonable range: 0.5 – 1.5m depending on capsule height.

---

## How to update this doc

After each session:

1. Rewrite the **Resumption Brief** completely. It must reflect *right now*,
   not history. If you find yourself adding to it instead of replacing, the
   item probably belongs in the Tracker.
2. Move "in progress" items in the Tracker to "Done this v0.0 cycle" as they
   finish. Add new entries to Deferred / Known Limits as they emerge.
3. If the Tracker is hard to navigate, it's too big. Move older "Done"
   entries into a one-line summary like "Phase X complete (commit abc123)"
   and trust git for the detail.
4. If updating this doc took more than ten minutes, something is wrong with
   its shape and it's worth ten more minutes fixing the shape than letting
   it grow past the point of maintenance.
