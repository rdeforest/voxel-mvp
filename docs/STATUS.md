# Project Status

> **Maintenance contract:** the "Resumption Brief" must reflect the current
> moment. The "Tracker" below it can drift a little. If updating this doc
> after a session takes more than ten minutes, it's too big — shrink it.

---

## Resumption Brief

### Active thread (2026-06-16): full-project code review (two-pass) — review now, edits after

**The plan (Robert's call).** Before the DC cleanup pass + bug bash, do a complete code review in **two passes**:
1. **Pass 1 — Claude reviews the whole project and acts on it.** Both levels:
   - *Low-level:* code-style fit, better loop/branch handling, branch→data-structure conversions, split-too-big /
     merge-too-small, naming, vertical alignment, comment density.
   - *High-level:* single-responsibility (is an object doing >1 thing?), duplication (are two objects doing the
     same thing?), needless recompute, data moved that needn't be.
2. **Pass 2 — Robert reads every file, edits to taste, asks questions where the code isn't self-explanatory.**
   Claude extracts going-forward instructions from each of Robert's diffs (→ memory/feedback) and Robert builds
   a deeper mental model (currently ~VoxelFarm-blog level).

**Performance is known-poor and that's accepted for now** — Robert prioritizes forward progress over optimization/
debugging. So Pass 1 flags perf structurally (needless recompute, data churn) but does **not** chase frame time.

**Status:** Pass 1 done — reviewed (8 parallel subsystem reviews) + applied on `refactor/review-pass-1` (4 commits,
GUT 207/206 pass/1 pending/0 fail throughout):
- **`4e57cad`** delete `SparseVoxelOctree` + the GDScript SVO prototypes (`voxel_octree`/`octree_mesher`) + `dcgen`
  (`DcSubstratePreview`) + their tests; relocate the `terrain_surface` oracle to `EditStore`. −1834 lines. *(This
  pulled the SVO/dcgen prototype deletions FORWARD from the cleanup pass; the clipmap `DCTerrainManager` deletion
  still belongs to that pass.)*
- **`624e204`** consolidate duplicated GDScript: new `TerrainProbe` / `OverlayMaterial` / `PhysicsUtils` /
  `VoxelUtils.euler_basis` shared homes; single-source `TERRAIN_MATERIAL_PATH` / `SURFACE_NUDGE` / `PLAYER_CLEARANCE`
  into `VoxelConstants`; `FloodViz` drives a `GroundFlood`; event-bus `_remove_matching` no longer erases mid-iterate.
- **`23403e4`** dedup the DC mesher's leaf-decision logic (`want_leaf`/`sample_leaf`/`discard_children`) — the
  grow==fresh-build invariant no longer hand-synced across build/reconcile/make_leaf.

**Two review findings were FALSE POSITIVES (verified, not applied):** the mat3 SVD "double-flip" is correct (the
both-improper case has det F≥0, the double-negate is intended); the MPM sand-viscosity flag is the already-known
*pending* repose-tuning test, not a new bug.

**Deferred (recommend separate focused passes):** emit-via-`StoreWrite` consolidation (changes `terrain_sdf_changed`
footprint the structural layer subscribes to — wants event-coverage tests); C++ constants module (low value, MPM
paused, the gravity dup self-resolves when PBD retires); the LOW structural-perf items (per-frame Action rebuild,
`perf.gd` O(n) ring) per the flag-don't-chase steer.

**Pass 2 underway (2026-06-16):** Robert reads file-by-file leaving `RdF:` comments; Claude applies fixes + extracts
guidance (memories: [[group-related-params]], [[comments-why-not-what-design-to-docs]], [[no-pimpl-pattern]]). His
first lens — too-many-parameters / doing-too-much — drove a re-review (param groups: `EditEntry`, `ActionContext`,
`TerrainParams`, `ViewParams`) and these further commits (GUT green throughout, count now 193 after deleting clipmap tests):
- **`3b8c3a5`** `ActionContext` — bundle the store/player/integrity/pbd tail every Action ctor repeated.
- **`3464f9c`** drop the redundant `box` arg from `VoxelImprint.apply` (held the `Brush` bundle — touches CsgAction core).
- **`d58e8ce`** the **DC cleanup pass** (brought forward): delete the clipmap render (`DCTerrainManager`), the splice
  path (`DCEditSplicer` + C++ `mesh_subregion`), `DcMeshAudit`, their tests + console/world wiring (~1700 lines).
  **Key finding:** `mesh_clipmap`/`remesh` are NOT clipmap-only — collision, falling chunks, and ~10 test oracles use
  them, so they STAY. Cleaned the mesher header comments (answered the `RdF:` notes); `dc_octree_mesher.h` is ready
  for a fresh read.

**RdF items status:** `mesh_subregion` DELETED; over-long `mesh_clipmap` comment TRIMMED → docs ref. **DEFERRED (with
reasons):** un-pimpl (`DCOctreePersist` still holds the `Clipmap` `mesh_clipmap` needs — doesn't collapse cleanly) and
`mesh_clipmap`'s 20 params (load-bearing + GDScript-binding-constrained across ~17 positional call sites).

**Remaining recommended (queued):** `EditEntry` typed record (the `entry[0..3]` work tuples — behavior-sensitive),
`Brush` bundle, internal `TerrainParams` (C++), the name+comment sweep on live files, `mesh_world` `ViewParams`. Then
the **bug bash** (`docs/bugs/`), then MPM (doc 12) / v0.1 backlog (5.5g/h).

**TODO (vocabulary sweep): "terrain" → "matter".** Robert blessed **matter** as the umbrella for "any solid the voxels
describe, natural or built" (see [[matter-is-the-umbrella-term]]); reserve "terrain" for *natural generated ground*,
keep "material" = per-cell type. Sweep code + comments + docs renaming the umbrella uses (not the genuine-natural-ground
ones — judgment per site). Fold into the name+comment sweep. Bare `Vector3(0.5,0.5,0.5)` cell-centers should also become
`VoxelConstants.VOXEL_CENTER_OFFSET` while touching files (mpm_structure.gd still has ~4).

**Pass-2 read progress (which files Robert has walked, where to resume):**
- [~] `engine/voxel_dc/` — **PAUSED, come back later.** `dc_octree_mesher.h` fully read (RdF items resolved).
  `dc_octree_mesher.cpp` only ~line 100 of 1409 (`Level::build_mip`/`append_reduced_level` reviewed + cleaned).
  Robert started here only because it sorts first (engine < scenes, dc_octree first in the dir) — *not* because it's
  the right starting point. It's the hardest file; resume after the easier ones. Rest of `engine/voxel_dc/` unread.
- [ ] `scripts/` — in progress. Done: `voxel_utils.gd` (Robert authored it recently, no changes), `tools/ncls`
  (his own non-comment-LOC counter, no review needed). Deferred: `voxel_constants.gd` ("does what it says on the
  tin"; maybe revisit later to shorten comments).
- [ ] `scenes/` — unread
- [ ] `test/` — unread (lower priority)
Suggested resume order when picking back up: a small leaf file first (e.g. `scripts/voxel_constants.gd`,
`scripts/voxel_utils.gd`, an `actions/*.gd`) to build momentum, then back to `engine/voxel_dc/` for the C++ heavy lifting.

### Prior thread (2026-06-15): doc 17 done — dcworld IS the render

**Docs 14 + 16 DONE; doc 17's world-octree is now THE production render (GPU-verified visually).** The path:
P1 surface-sparse prune (concentric world-anchored min/max accel) → P2 graded floor from the ONE knob
`eps_px`, driven by the budget controller (self-tunes vs frame time + mesh lag, ~100/500 ms; settles ~eps 94)
→ P2.5 incremental band-diff (a move refines approached / coarsens receded / grafts+evicts the window edge,
re-meshing only the changed band) → P3 swap (`dcworld` enabled at startup, production shader + palette;
clipmap kept as the `dcmanager` comparison fallback). Perf overlay shows live `eps_px` + mesh-lag.
GUT 233 / 232 pass / 1 pending / 0 fail. **Merged to `master` (`ca83017`)** — `feat/dc-persistent-octree-cache` folded in.

**Deferred BY CHOICE (Robert's sequence: finish all `started/` docs → code cleanup pass → bug bash):**
- The **inside-coverage cracks** ride along on the render — tracked in [`docs/bugs/`](bugs/00_INDEX.md)
  (proactive accumulate-fine-QEF fix proposed), for the **bug bash**.
- **Deleting** the old parallel renders (clipmap + geomorph + `dcgen`/SVO) is the **cleanup pass** — kept as
  fallbacks for now.

**`started/` docs reconciled (2026-06-15):** `05-phase-5_5` is the v0.1 backlog, now honest — 5.5a/b done,
5.5c/5.5f **superseded by MPM** (doc 12), 5.5d/e → v0.2, **5.5g (construction polish) + 5.5h (QoL/perf/bugs)
are the live v0.1 work** (some 5.5h items landed or MPM-mooted). doc 17 is done (render swap). So per the
sequence the next step is the **DC code cleanup pass**: delete the retired parallel renders dcworld replaced
(camera-centered clipmap + geomorph + `dcgen`/SVO + the GDScript SVO substrate prototypes), then the **bug
bash** (`docs/bugs/`). After that, the open feature threads are MPM (doc 12) and the v0.1 backlog (5.5g/h).

### Open thread (paused, 2026-06-11): MPM continuum-physics substrate — spike done, VERDICT = GO

**The pivot.** GUI-testing parts-as-voxels surfaced PBD's structural limits — a beam on a peak
**sags through the mountain** (no terrain contact) and break-off chunks **lock mid-fall**. PBD
is the mass-spring approximation; the manifesto says don't keep an approximation for *effort*
reasons. So the structural sim is moving to **continuum mechanics via MPM** (Material Point
Method): terrain, parts, debris deform/fracture/flow/settle under one solver, its grid IS our
voxel grid, topology change (fracture **and** merge) is intrinsic, contact resolves on the grid.
Spec + verdict: **`docs/roadmap/design/12-mpm-structural-substrate.md`**. MPM **subsumes** PBD,
`VoxelChunkBody`, the falling-body classifier, and parts-as-voxels **Stages 5–6** (merge-back
becomes the MPM freeze transition).

**Done: the MPM spike (`engine/voxel_dc/mpm_sim.*` + `mpm_material.*` + `mat3.*`,
`test/test_mpm_sim.gd`, 183/183 GUT).** Isolated MLS-MPM (APIC, double precision), not wired into
the game. Proven headlessly: stable core loop; verified 3×3 SVD; fixed-corotated + neo-Hookean
elasticity; **EditStore SDF as a grid collider — a stiff body rests ON terrain, doesn't pass
through (the beam-through-mountain fix)**; Drucker-Prager sand flows to a repose pile; **sparse
sleeping** (settled = exact no-op, lossless state; wakes on disturbance — the doc-12 boundary-
elimination path). Cost is per-particle-linear, SVD-dominated (corotated 2.4 µs/particle; 8 k =
19.6 ms single-thread CPU). **GO**: physics correct; real-time needs the known runway (fast 3×3
SVD, multi-thread/GPU, sparse sleeping) — single-GPU on the 5090 (dual-GPU deferred, doc 12).

**NEXT (doc 12 staging, post-spike):** (2) graduate the MPM core toward real-time — fast 3×3 SVD
(McAdams 2011) + multi-thread, then GPU compute; (3) **the EditStore thaw/freeze coupling** (the
one remaining *research* risk — seeding particles from the field on failure, freezing settled
material back, crack-free against static terrain); (4) replace PBD, retiring it + `VoxelChunkBody`
+ the falling-body classifier, closing Stages 5–6 as emergent. Sub-metre parts and the overlap-
material rule (PartIndex) ride along later.

**Parts-as-voxels Stages 1–5 (done, the substrate MPM rides on)** — `3735bf7`, `4eaf553`,
`228b417`, `059f36b`, `ffc725c`. Parts are imprinted voxels (`ConstructionAction`+`VoxelImprint`),
identity in the `PartIndex` sidecar; the old `PartSupport` spine was deleted (S4, 998 lines); S5's
`VoxelChunkBody` DC-meshes break-offs. Catalog: `beam` 6×2×2 Wood + `slab` 4×2×4 Stone (2/4/6 m
are temporary testing sizes — doc 03 Nyquist #1). **Stage 6 (merge-back) is PARKED** — it becomes
the MPM freeze transition, don't build it twice. **Known issue:** placing a part over another
recolours the overlap (use PartIndex). **GUI-checked through S4**; S5's falling-chunk look not yet
eyeballed (now moot — MPM replaces that path).

---

## Tracker

### v0.0 — Phase status

| Phase | State | Notes |
|-------|-------|-------|
| 0 — Foundation | Complete | godot + godot_voxel build chain, walking-around prototype |
| 2 — Terrain Modification | Complete | dig, fill, flatten with refuse-don't-deform |
| 5 — Building System | Functionally complete for v0.0 | Parts, structural integrity, cave integrity, pillar reinforcement all working; SDF seam matching deferred to v0.1+ |
| Cleanup pass | Complete | Plan fully landed or made moot by the Phase 6 / PBD deletions (collapse_detector, part_support, integrity_debug); plan doc retired |
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

> **Deferred *bugs* (defects) now live in [`docs/bugs/`](bugs/00_INDEX.md)** — one file per bug with
> diagnosis + a proposed fix. Includes the DC world-octree inside-coverage cracks (blocks doc 17 P3),
> reversed ridge triangles, soft crease normals, the edit-remesh padding gap, and distant shadow shimmer.
> The entries below are design/tuning *limits*, not defects.

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
