# Project Status

> **Who this is for:** Robert. Agents read `CLAUDE.md`.
>
> **Maintenance contract:** the Resumption Brief must reflect the current
> moment. Rewrite it, don't append to it. The Tracker below may drift.
> If updating this doc takes more than ten minutes, it's too big — shrink it.

---

# Resumption Brief

*Last rewritten: 2026-09-13*


## Where things stand right now

Work stopped in mid-June and resumed 2026-09-13 after a three-month gap.

Branch situation is resolved. What looked like nine branches was one line of
work plus five empty pointers. Everything real lives on
`audit/claude-code-review` (52 commits ahead of `master`), which despite its
name is the **M-thesis scale-up**: mmap disk-paged cell arena, 725M cells,
incremental grow (c1–c4a), hot/cold cell split (296 → 124 B), parallel
bottom-up DC build, plus the incremental-emit bug hunt at the tip.

`master` has two commits the branch lacks (`6a5ed6f`, `49cf512`) that
re-apply branch work; the merge is a real merge, not a fast-forward.


## The active thread: full-project code review, pass 2

The plan, in two passes:

**Pass 1 — Claude reviews and applies.** Low-level (style fit, loop/branch
handling, branch→data-structure conversion, split/merge, naming, comment
density) and high-level (single responsibility, duplication, needless
recompute, data moved that needn't be).

**Pass 2 — Robert reads every file**, edits to taste, asks where the code
isn't self-explanatory. Claude extracts going-forward guidance from each
diff. The point is the mental model as much as the code.

Performance is known-poor and that's accepted. Pass 1 flags perf
*structurally* (recompute, churn) but does not chase frame time.

### Pass 1: done

Applied on `refactor/review-pass-1`, since merged to master. GUT green
throughout (207/206 pass/1 pending/0 fail).

- `4e57cad` — delete `SparseVoxelOctree`, the GDScript SVO prototypes
  (`voxel_octree`/`octree_mesher`), `dcgen` (`DcSubstratePreview`) and their
  tests; relocate the `terrain_surface` oracle to `EditStore`. −1834 lines.

- `624e204` — consolidate duplicated GDScript. New shared homes:
  `TerrainProbe`, `OverlayMaterial`, `PhysicsUtils`, `VoxelUtils.euler_basis`.
  Single-sourced `TERRAIN_MATERIAL_PATH` / `SURFACE_NUDGE` /
  `PLAYER_CLEARANCE` into `VoxelConstants`.

- `23403e4` — dedup the DC mesher's leaf-decision logic
  (`want_leaf`/`sample_leaf`/`discard_children`).

**Two findings were false positives, verified and not applied:** the mat3 SVD
"double-flip" is correct (both-improper case has det F≥0; the double-negate is
intended), and the MPM sand-viscosity flag is the known *pending* repose-tuning
test, not a new bug.

**Deferred to separate focused passes:** emit-via-`StoreWrite` consolidation
(changes the `terrain_sdf_changed` footprint the structural layer subscribes
to — wants event-coverage tests first); a C++ constants module (low value);
the LOW structural-perf items (per-frame Action rebuild, `perf.gd` O(n) ring).

### Pass 2: in progress, this is where to resume

Robert reads file-by-file leaving `RdF:` comments; Claude applies fixes.

Guidance extracted so far: group related params; comments say *why* not
*what*, design goes to docs; no pimpl pattern.

His first lens — too many parameters, doing too much — drove a re-review and
these commits:

- `3b8c3a5` — `ActionContext` bundles the store/player/integrity tail every
  Action constructor repeated.
- `3464f9c` — drop the redundant `box` arg from `VoxelImprint.apply`.
- `d58e8ce` — the DC cleanup pass, brought forward: delete the clipmap render
  (`DCTerrainManager`), the splice path (`DCEditSplicer` + C++
  `mesh_subregion`), `DcMeshAudit`, their tests and wiring. ~1700 lines.
  **Key finding:** `mesh_clipmap`/`remesh` are *not* clipmap-only — collision,
  falling chunks and ~10 test oracles use them. They stay.

Two `RdF:` items deferred with reasons: un-pimpl (`DCOctreePersist` still holds
the `Clipmap` that `mesh_clipmap` needs — doesn't collapse cleanly), and
`mesh_clipmap`'s 20 params (load-bearing and GDScript-binding-constrained
across ~17 positional call sites).

**Queued after that:** `EditEntry` typed record (the `entry[0..3]` work tuples,
behavior-sensitive), the `Brush` bundle, internal `TerrainParams` in C++, the
name-and-comment sweep on live files, `mesh_world` `ViewParams`.

### Read progress — which files have been walked

- `engine/voxel_dc/` — **paused, come back later.** `dc_octree_mesher.h` fully
  read, `RdF:` items resolved. `dc_octree_mesher.cpp` only to ~line 100 of
  1409 (`Level::build_mip` / `append_reduced_level` reviewed and cleaned).
  Started here only because it sorts first, *not* because it's the right
  starting point. It's the hardest file. Rest of the directory unread.

- `scripts/` — in progress. Done: `voxel_utils.gd` (recently authored, no
  changes), `tools/ncls`. Deferred: `voxel_constants.gd` (does what it says on
  the tin). `scripts/structural/mpm_structure.gd` started — renamed
  `PARTICLE_SIZE`→`DEBUG_CUBE_SIZE` and `0.5,0.5,0.5`→`VOXEL_CENTER_OFFSET` —
  then abandoned for the accel-bake work below.

- `scenes/` — unread.
- `test/` — unread, lower priority.

**Scale, measured 2026-09-13:** ~5k lines across 147 files under `scripts/`,
~5k across 25 under `engine/`. At one file per session this is not finishable
as-is. Plan: sort by line count descending, give real sessions to the top ~20,
batch-skim the long tail, and keep a review ledger so the pile visibly shrinks.

**Suggested resume:** a small leaf file to build momentum (`voxel_constants.gd`,
an `actions/*.gd`), then back to `engine/voxel_dc/`.


## Two perf threads in flight

### Incremental accel bake (doc 17, P1 nit)

`grow_world` re-bakes the whole concentric min/max prune accel on every move.
That's a fixed mesh-lag cost independent of `eps_px` — the floor that stops the
controller refining.

Fix: scrolling-buffer reuse, mirroring `EditStore::fill_region`. Res-snap each
accel level so a move scrolls it cell-aligned, copy the overlap, sample only
the entered shell.

Unlocks lower per-move lag *and* idle progressive refinement (cheap grows let
the controller keep refining a held view toward the 0.25 m floor).

**Considered and rejected:** heightfield-derived accel (O(dim³)→O(dim²)). It
assumes the generator is forever a heightfield. Manifesto says no.

### Multithread the mesher

The DC remesh is a single `WorkerThreadPool` task — one core does the whole
build while the other 23 idle. At meshlag 20s / coverage 256 the controller
settled at eps 19 (~5s remesh) because the refine target is `mesh_ceil*0.2`,
not because of the ceiling.

Plan, in order:

1. **Instrument the phases** (accel-bake vs build-sample vs collapse/emit ms).
   Diagnose before fixing — we don't yet know where the 4s goes. Octree
   descent plus multi-octave FastNoiseLite over tens of millions of samples
   could be honest compute.
2. **Runtime thread-count knob** (`dcthreads` console). Also the instrument
   for the SMT question: sweep past physical-core count — keeps scaling means
   latency-bound, plateaus means compute-bound.
3. **Parallelize the accel bake** — pure `dim³` independent loop, safe first
   win.
4. **Parallelize build leaf-sampling** (the likely-dominant cost) via a
   structure-pass-then-parallel-sample-pass split. Tree-structure decisions
   need only the accel and floor, so leaf QEF sampling can be a separate
   parallel pass, sidestepping the shared node-array/free-list thread-unsafety.

Byte-identical build tests gate parallel correctness.


## Standing TODO: vocabulary sweep, "terrain" → "matter"

**Matter** is the umbrella term for any solid the voxels describe, natural or
built. Reserve **terrain** for naturally generated ground. **Material** stays
per-cell type.

Sweep code, comments and docs for umbrella uses — judgment per site, don't
rename the genuine natural-ground ones. Fold into the name-and-comment sweep.

While touching files, bare `Vector3(0.5, 0.5, 0.5)` cell-centers should become
`VoxelConstants.VOXEL_CENTER_OFFSET` (~4 remain in `mpm_structure.gd`).


## Paused threads

### MPM continuum-physics substrate — spike done, verdict GO

GUI-testing parts-as-voxels surfaced PBD's structural limits: a beam on a peak
sags through the mountain (no terrain contact), break-off chunks lock mid-fall.
PBD is the mass-spring approximation and the manifesto says don't keep an
approximation for effort reasons.

So the structural sim moves to **MPM**. Terrain, parts and debris deform,
fracture, flow and settle under one solver; its grid *is* our voxel grid;
topology change is intrinsic; contact resolves on the grid. MPM subsumes PBD,
`VoxelChunkBody`, the falling-body classifier, and parts-as-voxels stages 5–6.

Spec and verdict: `docs/roadmap/design/12-mpm-structural-substrate.md`.

**The spike** (`engine/voxel_dc/mpm_sim.*`, `mpm_material.*`, `mat3.*`,
`test/test_mpm_sim.gd`, 183/183 GUT) proved headlessly: stable core loop;
verified 3×3 SVD; fixed-corotated and neo-Hookean elasticity; EditStore SDF as
a grid collider, so a stiff body rests *on* terrain (the beam-through-mountain
fix); Drucker-Prager sand flowing to a repose pile; sparse sleeping (settled is
an exact lossless no-op, wakes on disturbance).

Cost is per-particle-linear and SVD-dominated: corotated 2.4 µs/particle, so
8k particles is 19.6 ms single-threaded.

**Next, per doc 12:** graduate toward real-time (fast 3×3 SVD per McAdams 2011,
then multi-thread, then GPU compute) → the EditStore thaw/freeze coupling,
which is the one remaining *research* risk → retire PBD, `VoxelChunkBody` and
the falling-body classifier.

Note: `a0e9965` on the current branch already removes PBD. Merging lands that.

### Parts-as-voxels, stages 1–5 — done

`3735bf7`, `4eaf553`, `228b417`, `059f36b`, `ffc725c`. Parts are imprinted
voxels; identity lives in the `PartIndex` sidecar; the old `PartSupport` spine
is deleted (998 lines). Stage 6 (merge-back) is **parked** — it becomes the MPM
freeze transition, don't build it twice.

**Known issue:** placing a part over another recolours the overlap. Use
PartIndex.


## Immediate next actions

1. Merge `audit/claude-code-review` into `master`; delete the dead branches.
2. Update this brief to reflect the merged state.
3. Bug bash — see `docs/bugs/00_INDEX.md`.
4. Resume pass 2 with the line-count-sorted plan above.


---

# Tracker

*Slower-moving. Allowed to drift.*


## Where the authoritative lists live

Rather than duplicating them here:

| Question | Doc |
|---|---|
| Why are we doing this at all? | `docs/MANIFESTO.md` (wins over everything) |
| What is the game? | `docs/roadmap/vision/06-what-the-game-is.md` |
| What version answers what question? | `docs/roadmap/implementation/01-version-strategy.md` |
| What's in the v0.1 backlog? | `docs/roadmap/implementation/05-phase-5_5-*.md` (FEAT030–047) |
| What's deferred and why? | Same, plus `docs/completed/` |
| Which commitments are immovable? | `docs/roadmap.md` → Architectural Commitments |
| What defects are open? | `docs/bugs/00_INDEX.md` |
| Where does the code live? | `CLAUDE.md` |

The v0.0/v0.1 phase-completion tables that used to live here duplicated
`docs/roadmap/implementation/` and `docs/completed/`. They're gone; those are
the source of truth. Git log is the authoritative narrative of what shipped.


## Known limits — recorded, not fixed

These are design and tuning *limits*, not defects. Defects live in
`docs/bugs/`.

- **Flatten preview z-fights with the surface it's matching.** Cosmetic.
  Cleanest fix is a small forward offset on the preview plane normal.

- **`_resume_unfinished_floods` budget starvation.** Components larger than
  `DETECTION_BUDGET` (500 voxels) take multiple settled frames to fully detect.

- **`PLAYER_CLEARANCE = 1.0 m`** in Fill/Flatten is a guess.

- **Lazy-expansion cascade per dig is bounded by material decay budget.** For
  STONE (decay 0.05) the cascade reaches ~20 cells. Future load-propagation
  will need its own cascade rules.

- **`_recompute_column_low` scans `voxel_data`.** Fast at ~10k tracked cells;
  replace with a per-column ordered set if the tracked count grows.

- **Cross-beam placement validates but doesn't mutually support.** Placing one
  beam through another succeeds (intersection is a valid attachment per
  `validate`), but the new beam only sees support through "cell below."
  Welding is v0.1.

- **Vertical-on-horizontal beam support sometimes fails.** Likely a
  coordinate-snap edge in the footprint math.

- **Obscured stress-overlay tints visible cells.** With `H` on, the
  obscured-pass corner brackets render unconditionally (no_depth_test). A
  depth-comparison shader could discriminate; the faint tint is acceptable
  for now.


---

# How to update this doc

1. **Rewrite the Resumption Brief completely.** It must reflect *right now*,
   not history. If you're appending rather than replacing, the item belongs in
   the Tracker or in one of the docs the table above points at.

2. **Don't restate what another doc owns.** Link to it. This doc's job is
   "where am I and what's next," nothing else.

3. **If it took more than ten minutes, something is wrong with its shape.**
