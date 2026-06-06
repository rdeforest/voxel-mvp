# Project Status

> **Maintenance contract:** the "Resumption Brief" must reflect the current
> moment. The "Tracker" below it can drift a little. If updating this doc
> after a session takes more than ten minutes, it's too big — shrink it.

---

## Resumption Brief

### Active thread (2026-06-05): PBD structural physics (Poly Bridge ∪ World of Goo)

**Plan:** `~/.claude/plans/i-m-confused-the-mesher-virtual-popcorn.md` (approved).
Replace the cellular support/collapse core (`TerrainSupport` + `PartSupport` +
`CollapseDetector`) with a real breakable **mass-spring sim via Position-Based
Dynamics (XPBD)**: members carry tension+compression and fail over a limit;
cantilevers/bridges built too far out (not held below or pulled above) fail
emergently. One particle per tracked cell, auto cross-braced; natural terrain =
pinned anchors; detached chunks → existing `FallingBodyFactory` + falling-body
lifecycle (reused). Phased, with the PBD system running **parallel / viz-only
until it reaches parity**, then a switch-flip + delete (don't delete 3 working
systems before parity). Headless GUT per phase. See the plan for phases 1–7.

**Two deferred voxel decisions made this session (recorded, NOT this thread):**
- Voxel substrate → **adaptive-density octree**; godot_voxel is **not sacred**
  (replaceable where it limits us). See [[adaptive-octree-substrate]] /
  `docs/roadmap/design/03-dc-qef-geometry.md` §"Decisions taken".
- **Parts-as-voxels** (imprint parts into SDF + material channel; one field/mesher/
  integrity) rides on that octree — deferred until we return to voxel work.

### Done: F2 LOD seams via our own meshing layer (path b) — DC is the default render

Terrain meshing migrated Transvoxel → our **Dual Contouring** (`VoxelMesherDC`
per-block for collision; `DCOctreeMesher` C++ octree-clipmap for the render). The
path-b "own meshing/render layer" is complete: `DCTerrainManager` renders a
crack-free LOD clipmap (C++, ~44–62ms off-thread) as the default terrain render,
edit-driven re-mesh, with a `dcsolo`/`dcmanager` console fallback to godot_voxel.
Build order #1–#8 below.

Path-b build order / progress:
- ✅ **#1 fast region read** — `DCRegionReader.read_sdf_lod0` (C++, bulk
  `VoxelData::copy`, transient store grab). Required the **SCsub ABI fix** (mirror
  godot_voxel's `VOXEL_ENABLE_*` defines — see [[voxel-dc-abi-defines]]) and
  `cache_generated_blocks = true` in `world._enter_tree` (reads ~450ms → 0ms).
- ✅ **#2 worker-thread meshing** — folded into #3's first increment.
  `OctreeDC.build_field_arrays` is the worker-safe (pure-CPU, no RenderingServer)
  half; `build_field` stays the main-thread `ArrayMesh` wrapper.
- ✅ **#3 the manager — distance-graded bubble (GUI-verified).**
  `DCTerrainManager` (`scripts/dc/dc_terrain_manager.gd`): follows the player,
  reads+bakes a region on the main thread, meshes it on a `WorkerThreadPool` task
  over the immutable baked field, swaps the `ArrayMesh` in on completion,
  re-meshing past `RECENTER_DISTANCE`. Depth-6 bubble, distance-graded `refine`
  (`LOD_QUALITY` tunes falloff). `dcmanager [on|off]`. No octree-balance pass
  needed — point-location meshing stitches any level jump crack-free (see
  [[dc-no-balance-pass]], guarded by `test_octree_dc`).
- ✅ **#4 data-only mechanism.** `DCTerrainManager.set_data_only()` flips the
  terrain's `render_layers_mask` to 0 (hides godot_voxel's render; collision/data/
  streaming/edits untouched — collision is a separate static body), restores on
  disable/exit. `dcsolo [on|off]`. *Mechanism only* — looks right once coverage
  reaches view distance (the clipmap, below).
- ✅ **#5 edit-inclusive multi-LOD read.** `DCRegionReader.read_sdf_lod(terrain,
  lod, origin, size)` (C++): generator baseline + overlay of present data-store
  blocks (edits live there as downsampled mips). LOD0 routes through `copy()`.
  **Edits render identically at every LOD** (a first-class-citizen invariant —
  see [[edits-first-class]]). GUI-verified via the `dclod [lod]` probe.
- ✅ **#6 the LOD clipmap (GUI-verified).** `SdfClipmap`
  (`scripts/dc/sdf_clipmap.gd`): nested levels centred on the player, level k at
  LOD k covering 2^k the extent / same sample count; `value()` picks the finest
  level containing the point (single-valued → crack-free), `target_cell_size()`
  drives the refine so cell size and data LOD transition together. The manager
  builds it (4 reads on main: 32/64/128/256m at LOD 0/1/2/3) and meshes one
  depth-8 octree on the worker. Covers view distance, no undersampling holes,
  edits everywhere, `dcsolo` usable. `log_timings` prints read/mesh ms per
  recenter.
- ✅ **#7 C++ mesher (GUI-verified, matches the per-block VoxelMesherDC render).** `DCOctreeMesher`
  (`engine/voxel_dc/dc_octree_mesher.cpp`): faithful C++ port of `SdfClipmap` +
  `OctreeDC` (full subdivision — no adaptive heuristic; C++ speed makes it
  unneeded). QEF extracted to `dc_qef.h`, shared with `VoxelMesherDC`. Manager
  meshes via it on the worker. **~44ms vs ~1.4–2.8s GDScript** (~40×). Parity-
  tested on real terrain (`test_dc_real_terrain.gd`: sound + matches GDScript vert
  count). GDScript `OctreeDC`/`SdfClipmap` stay as prototype/preview/test mesher.
  - NOTE: surface-adaptive pruning was abandoned — magnitude-based prune shatters
    on slopes (the terrain SDF overestimates true distance on slopes, see
    [[dc-sdf-not-unit-distance]]); sign-based couldn't be proven to fix the live
    break headless. C++ full subdivision sidesteps it.
  - NOTE: C++ uses field-gradient normals, no crease-split yet (the GDScript
    `MeshNormals` step). Fine on terrain; port crease normals if sharp edges on
    edits/structures read too soft.
- ✅ **#8 DC is the default render (path-b finalized).** `start_default()` in
  `world._ready` enables the manager and hides godot_voxel's per-block render once
  our first mesh lands (no startup void); `dcmanager`/`dcsolo` override. Coverage
  bumped to `LEVELS = 6` (~1024m, ~62ms off-thread) so the far view survives the
  swap. Edit-driven re-mesh: the manager subscribes `terrain_sdf_changed` and
  re-meshes so digs/builds show with godot_voxel hidden (whole-clipmap for now).
  Collision stays on `VoxelMesherDC` (godot_voxel's static body, unaffected by the
  render mask). In-game **Toast** log (top-right, `scripts/ui/toast.gd`) reports
  save/load success/failure.
  - ⏭️ **NEXT (deferred cleanup, not blocking):** single-mesher consolidation —
    drive collision from our octree mesh so godot_voxel can stop per-block visual
    meshing (it still meshes hidden blocks = wasted CPU); C++ crease normals (the
    C++ mesher uses field-gradient normals, may soften sharp edges on built
    structures); incremental edit re-mesh (vs whole-clipmap ~62ms).

**Console tools to resume:** `dcmanager [on|off]` (the threaded graded bubble),
`dcsolo [on|off]` (data-only: hide godot_voxel's render), `dclod [lod]` (probe one
LOD's edit-inclusive read+mesh around you), `dcspike` (uniform DC of a region,
magenta), `dcoctree` (multi-LOD crack-free octree DC w/ a fine/coarse seam, cyan)
— all read VoxelData via `DCRegionReader` and render our own mesh; `lod [dist]` (live
pop-in tuning); `vdebug [flag]` (godot_voxel debug overlays); `set`/`get` (shader
uniforms incl. `debug_lod` / `debug_normal` visualizers).

**Uncommitted on purpose:** `scenes/world/world.tscn` (Robert's `lod_distance=96`
tuning + editor debug-shader defaults), `docs/F2-lod-seam-options.md` (scratch
decision doc — keep as reference). Deferred items have memories: LOD-boundary
cracks (this work), [[edit-remesh-padding-gap]], [[distant-shadow-shimmer]].

---

### Older brief (pre-DC-QEF, partly superseded)

*Last updated: Tools/activities UI overhaul, Limbo Console with
seven commands, four new verbs (Raise/Lower/FillVoxel/EmptyVoxel),
grass shader, free part placement, part-stress proximity
visibility, and the phantom-voxel deregistration fix are all in.*

**Where you are:** Construction + landscaping have reached a
"tantalizingly close to genuinely useful" point. Recent landings
(see Done list for the full chronological list):

- Tools/activities UI. Tab cycles three Tools (None / Landscape /
  Construction); 1-9 picks the activity within. Each tool remembers
  its last activity. None.Probe prints SDF + tracked + support state
  to the in-game console — useful for the phantom-strain class of
  bug.
- Limbo Console as a git submodule (pinned v0.7.0) plus seven
  starter commands: `set`, `reset`, `quiescent`, `parts`, `voxels`,
  `tp`, `quit_game`. Backtick toggles. `reset` rewinds to procedural
  defaults without touching the save files; F9 still restores.
- Four new verbs in `scripts/actions/`: Raise / Lower (bell-shaped
  brushes), FillVoxel / EmptyVoxel (surgical single-cell).
- Free part placement: drop the cell-snap; Shift+W/A/E + wheel
  adjusts the offset along view axes. Shift suppresses WASD
  movement (Shift+key is a *distinct* input from key alone).
- Grass shader: slope-based grass/dirt with 4-octave gradient noise
  driving a wind animation. Uniforms tweakable via the editor's
  Remote inspector or the `set` console command.
- Phantom voxels fixed: TerrainSupport's `terrain_sdf_changed`
  handler now deregisters tracked cells whose SDF has become air,
  not just registers newly-exposed cells.

19/19 GUT tests pass.

**Pick up here:**

1. **Rest of part-placement control.** Free placement landed; what's
   still wanted: snap-modifier hotkeys for explicit grid alignment,
   maybe rotation snapping, KSP-style parametric resize. Part
   placement is *close* to useful; one more polish pass would
   probably get there.
2. **Vertical-on-horizontal beam support bug.** Known-limit; the
   `_direct_part_supporter` cell-below check sometimes misses.
   Surfaces when the part-placement work needs it.
3. **Pick-and-stamp plane orientation.** Capture an example wall's
   plane to reuse for vertical flatten elsewhere. Same primitive
   supports "make a ramp, keep that plane for the next clicks." v0.2
   polish.
4. **Slow-step movement / edge-stop toggle.** Don't accidentally
   walk off structures you just built.
5. **Playtester binaries** (Linux/macOS/Windows via GitHub Actions).
6. **v0.1 gameplay scoping** — see `roadmap.md` Phases 1, 3, 4.

**Architectural status:** see the "Architectural commitments" list
in `roadmap.md` (single source). The summary: structural integrity
is the load-bearing thesis claim and works; bus decoupling means
adding a second indexer is a `subscribe()` call; falling-debris
classifies itself each tick into free/partial/full; persistence
gates on quiescence and trusts saved support values.

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
| 5.5b3 — Voxel-aware preview UI | Complete (`d2b7bbd`) | Per-cell highlighting via Action.preview() |
| 5.5c — Fracture as mesh extraction | Deferred to v0.2 | per roadmap |
| 5.5d — Multi-grid foundation | Deferred to v0.2/v0.9 | grid_id carried in payloads from day one |
| 5.5e — Per-channel non-SDF data | Deferred to v0.2/v0.9 | |
| Fallen-dirt-as-terrain | Complete (`250bf13`) | Falling bodies freeze on partial bury, integrate as tracked SDF on full bury |
| Free part placement (XYZ) | Complete (`9f2e36a`) | Shift+W/A/E + wheel adjusts offset along view axes |
| New verbs (Raise/Lower/FillVoxel/EmptyVoxel) | Complete (`3ebf5cf`) | Bell-shape + per-voxel surgical |
| Tools/activities UI | Complete (`3ebf5cf`) | Tab cycles tools, 1-9 picks activity, per-tool memory |
| Limbo Console + tunables + reset | Complete (`3ebf5cf`) | Backtick toggles; reset rewinds to procedural without losing saves |
| Grass shader on shallow slopes | Complete (`eedef27`) | Gradient-noise wind animation |

### In flight

*(nothing in flight — Phase 5.5b is the next scheduled work)*

### Bugs

| ID | State | Notes |
|----|-------|-------|
| 2c | Closed | Player fall-through fixed via `Action.validate()` refusal |
| 2a | Closed | Closed by the Phase 5.5b2 column-based flatten — each lateral column now cuts up to the reachable air within radius, not a single sheet |

### Architectural commitments

Moved to `roadmap.md` — single source of truth for the immovable
design decisions (engine pins, bus shape, persistence model, facade
composition, typed records, propagation strategy, etc.). When you
need to know "is X load-bearing?", look there.

### Done this v0.0 / v0.1 cycle

Recent items first. Older entries collapsed to one-liners — git log
is the authoritative narrative; this list is the cheat sheet.

**Recent (current cycle)**
- **Phantom-voxel deregistration fix** (`3ebf5cf`).
  `terrain_sdf_changed` handler now drops tracked records whose SDF
  has become air, symmetric with the existing register-on-boundary
  code.
- **Tools/activities UI** (`3ebf5cf`). Tab cycles three tools;
  1-9 picks activity within. None.Probe prints cell diagnostics to
  the console.
- **Limbo Console + commands + reset + tunable persistence**
  (`3ebf5cf`). Submodule pinned v0.7.0. Seven commands. Reset
  rewinds to procedural defaults without deleting save files.
  WorldSnapshot V3 (tunables) + V4 (tool_index/activity_indices).
- **Four new verbs** (`3ebf5cf`): Raise / Lower (bell-shaped) and
  FillVoxel / EmptyVoxel (surgical).
- **Free part placement** (`9f2e36a`). Shift+W/A/E + wheel adjusts
  offset along view axes; Shift suppresses WASD movement universally.
  Part-stress proximity visibility (matches IntegrityDebug pattern).
- **Grass shader** (`eedef27`). Slope-based grass/dirt with
  4-octave gradient-noise wind animation.
- **Voxel-aware preview UI (5.5b3)** + stress-indicator overhaul
  (`d2b7bbd`). ActionPreview / VoxelPreviewRenderer; IntegrityDebug
  rewritten on ImmediateMesh with spatial filter and obscured-pass
  toggle.
- **Voxel grid overlay** (`d761cb4`). G key, Chebyshev shells.
- **Fallen-dirt-as-terrain** (`250bf13`). Falling bodies classify
  each tick: free / partial-buried (freeze) / full-buried (integrate).
- **Phase 5.5b1+b2** (`15308bd`): AdditiveAction base + column-based
  honest flatten.
- **Phase 5.5a — voxel event bus** (`ee80b63`): autoload,
  channel-wide + per-cell subscribers, WeakRef lifetime, primitive
  vs derived event tiers.
- **Persistence** (`a4b95da`): VoxelStreamSQLite + WorldSnapshot.

**Earlier (pre-bus refactor)**
- Cleanup pass — typed records, facade-+-components split, player
  composition, support classification cascade, comment pruning,
  `docs/architecture.md` created (`704af67`, `78c398e`, `43e0d9c`).
- Materials → `.tres` refactor (`e00513b`).
- v0.0 thesis demo — action infrastructure, parts, structural
  integrity, cave integrity, lazy-expansion + bedrock, falling
  parts, debug viz, README + LICENSE (multiple commits, see git
  log).

### Deferred to v0.1+ (the "can I make it fun?" question)

| Item | Why deferred |
|------|--------------|
| SDF seam matching (Option A2) | Sub-cell parts can't be represented at 1m voxel resolution; better answered by physics-driven part-vs-terrain interaction |
| Welding / joining (intersecting parts mutually support) | Needs a joint/weld data model; current `_cell_to_part` stack doesn't represent shared structural attachment |
| Load propagation (top-down weight pass) | Pairs with falling damage and SDF-seam-as-physics |
| Falling damage (impact breaks parts, crumbles dirt) | Needs a damage model |
| Hinge-at-boundary collapse | Polish on falling drama |
| Rest of part-placement control (snap modifiers, rotation snap, in-game resize) | Free placement landed; quality-of-life keys still to come |
| Pick-and-stamp plane orientation | Click an example wall to capture its plane, reuse for vertical flatten elsewhere. v0.2 polish. |
| Slow-step movement / "stop at edge" toggle | Don't accidentally run off structures you're building. Edge detection on slopes/curves is the hard part. |
| Spinning-beam physics quirk | Vertical metal beam, falls, hits ground at angle, picks up angular momentum and gyroscopes off down the hill. Polish-stage observation; keep an eye out for similar weirdness. |
| Stress-overlay SDF-surface coloring | Aspirational — apply support color to the actual Transvoxel surface via shader/material override, instead of separate wireframes. The current per-cell wireframe overlay is the right MVP. |
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
- **Vertical-on-horizontal beam support sometimes fails.** A vertical
  beam placed on top of a cantilevered horizontal beam doesn't always
  pick up the horizontal beam's support, even though `_direct_part_
  supporter` checks the cell below. Likely a coordinate-snap edge in
  the footprint math; defer until the part-placement-controls work
  needs it.
- **Obscured stress-overlay overlay slightly tints visible cells too.**
  When `H` is on, the obscured-pass corner brackets render
  unconditionally (no_depth_test), so visible cells get a faint
  bracket overlay in addition to their full outline. A depth-comparison
  shader could discriminate; for MVP the overlay is faint enough that
  it reads as a tint, not noise.

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
