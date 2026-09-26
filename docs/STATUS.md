# Project Status

> **Who this is for:** Robert. Agents read `CLAUDE.md`.
>
> **Maintenance contract:** the Resumption Brief must reflect the current
> moment. Rewrite it, don't append to it. The Tracker below may drift.
> If updating this doc takes more than ten minutes, it's too big — shrink it.

---

# Resumption Brief

*Last rewritten: 2026-09-25*


## Where things stand right now

The branch merge is done. `master` is the only branch; the M-thesis scale-up
(mmap disk-paged cell arena, hot/cold cell split, parallel bottom-up DC build,
incremental-emit bug hunt) is on it. Verify with `git log --oneline -5` if in
doubt — this brief was rewritten from the refs, not the log.

The `dc_octree_mesher.cpp` header split (formerly
`docs/refactor-dc-octree-mesher-split.md`) has also landed:
`dc_sdf_source.h`, `dc_clipmap_source.h`, `dc_edit_store_source.h` and
`dc_octree.h` now hold the internals; the .cpp keeps `DCOctreePersist` and the
`DCOctreeMesher::` methods. The brief is retired.

**Demo check: done (2026-09-25).** Robert smoke-tested launch, generate,
dig, build and collapse for Jamin and Cecilia; nothing blocking turned up.

**Now: back to features.** Every change uses this loop: an Opus agent authors
the change, two Fable agents adversarially review the diff (one for
correctness, one for completeness), and an Opus agent applies the findings. GUT
gates each step.


## The active thread: preview perf, then construction (5.5g)

**Done (2026-09-25), committed:**
- `f11d284` fixed `sdf-sample-corner-vs-center`. Every cell now has one sample
  point, the cell centre (see [CODE-MAP §SDF conventions](CODE-MAP.md)), and
  every brush predicts exactly what it writes. It changed the engine
  (`EditStore` writes land on finer leaves), so **run `tools/build` after
  pulling.**
- `c9430a4` fixed `actions-untyped-work-tuple` and
  `construction-bury-check-single-point`. It adds a typed `LatticeEdit`
  record. Each action's ghost, events and safety refusal now come from the
  field it writes, so a sub-cell part can't slip past the safety check.

Robert checked it in play: Raise/Lower refusal near the player looks right,
and the desaturated ghost makes refusal easy to see. Single-voxel edits didn't
do what he expected; that's filed as a known unknown,
[`single-voxel-edits-unexpected`](bugs/single-voxel-edits-unexpected.md).

**Next: [`actions-preview-gdscript-slow`](bugs/actions-preview-gdscript-slow.md).**
The exact prediction made previews 5–10× slower (CSG 2.5 ms per frame). The fix
is to build the lattice in C++; caching was rejected. Then comes **FEAT089,
parts look like parts**, which blocks the rest of 5.5g. Volumetric worldgen
tier 1 (`planned/18`) is independent and can run alongside.

The same review loop filed four more bugs: EmptyVoxel safety, PartIndex
footprint, lattice upper-face writes, and MPM thaw events. See
`docs/bugs/00_INDEX.md`.

GUT: 192 tests, 190 passing, 2 pending, 0 failing.

*Section drafted by Claude.*


## Paused: full-project code review, pass 2

**Pass 1** (Claude reviews and applies) is done and merged: `4e57cad`,
`624e204`, `23403e4`. GUT green throughout.

**Pass 2** — Robert reads every file, leaves `RdF:` comments, Claude applies
fixes and extracts going-forward guidance. The point is the mental model as
much as the code.

Guidance so far: group related params; comments say *why* not *what*, design
goes to docs; no pimpl pattern.

Pass-2 commits: `3b8c3a5` (`ActionContext`), `3464f9c` (drop `box` from
`VoxelImprint.apply`), `d58e8ce` (delete clipmap render, splice path,
`DcMeshAudit`; ~1700 lines). `mesh_clipmap`/`remesh` stay — collision,
falling chunks and ~10 test oracles use them.

Deferred `RdF:` items: un-pimpl (`DCOctreePersist` holds the `Clipmap` that
`mesh_clipmap` needs) and `mesh_clipmap`'s 20 params (~17 positional call
sites, GDScript-binding-constrained).

**Queued:** the `Brush` bundle, internal `TerrainParams` in C++, the name-and-comment
sweep, `mesh_world` `ViewParams`.

### Read progress

- `engine/voxel_dc/` — paused. `dc_octree_mesher.h` fully read. The reviewed
  `Level::build_mip` / `append_reduced_level` code now lives in
  `dc_clipmap_source.h`. Everything else unread, including the big one,
  `dc_octree.h` (~75 KB, the irreducible `Octree` struct).
- `scripts/` — done: `voxel_utils.gd`, `tools/ncls`. Deferred:
  `voxel_constants.gd`. `structural/mpm_structure.gd` started (renamed
  `PARTICLE_SIZE`→`DEBUG_CUBE_SIZE`, one `VOXEL_CENTER_OFFSET`), unfinished.
- `scenes/`, `test/` — unread.

**Scale:** ~5k lines / 147 files under `scripts/`, ~5k / 25 under `engine/`.
Plan: sort by line count descending, real sessions for the top ~20,
batch-skim the long tail, keep a review ledger.

**Resume with** a small leaf file (`voxel_constants.gd`, an `actions/*.gd`),
then back to `engine/voxel_dc/`.


## Perf threads (queued)

**Incremental accel bake** (impl doc 17, P1 nit). `grow_world` re-bakes the
whole min/max prune accel every move — a fixed mesh-lag floor. Fix:
scrolling-buffer reuse mirroring `EditStore::fill_region` (res-snap each
level, copy the overlap, sample only the entered shell). Rejected:
heightfield-derived accel — assumes the generator is forever a heightfield.

**Multithread the mesher.** The DC remesh is one `WorkerThreadPool` task on
one of 24 cores. In order: (1) instrument phases (accel-bake / build-sample /
collapse-emit ms) before fixing anything; (2) `dcthreads` console knob, also
the SMT probe; (3) parallelize the accel bake; (4) parallelize leaf sampling
via a structure-pass-then-sample-pass split. Byte-identical build tests gate
correctness. (`g_mesh_threads` now lives with `Octree` in `dc_octree.h`.)


## Standing TODO: vocabulary sweep, "terrain" → "matter"

**Matter** = any solid the voxels describe, natural or built. **Terrain** =
naturally generated ground only. **Material** = per-cell type. Judgment per
site; fold into the name-and-comment sweep. (Cell centres are done: every
cell→point read goes through `VoxelUtils.sample_point`.)


## Paused threads

**MPM continuum substrate — spike done, verdict GO.** Spec:
`docs/roadmap/design/12-mpm-structural-substrate.md`. Next per doc 12: fast
3×3 SVD (McAdams 2011) → multi-thread → GPU compute → EditStore thaw/freeze
coupling (the remaining research risk). PBD is already removed on master.
The SVD reflection handling was re-verified correct; a regression test
feeding a `det F < 0` matrix and asserting `det(U)·det(V)` and `sign(σ₂)`
would lock that in before the fast-SVD rewrite.

**Parts-as-voxels, stages 1–5 — done.** Stage 6 (merge-back) is parked; it
becomes the MPM freeze transition. Known issue: placing a part over another
recolours the overlap — use `PartIndex`.


## Immediate next actions

1. Move the preview lattice into C++ (`actions-preview-gdscript-slow`).
2. Characterize `single-voxel-edits-unexpected` with Robert.
3. FEAT089: parts look like parts, then the rest of 5.5g, with worldgen tier 1
   alongside.


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
| What's in the v0.1 backlog? | `docs/roadmap/implementation/started/05-phase-5_5-architectural-maturation.md` (FEAT030–047) |
| What's deferred and why? | `docs/roadmap/implementation/planned/`; shipped work in `implementation/done/` |
| Which commitments are immovable? | `docs/roadmap/design/02-architectural-commitments.md` |
| What defects are open? | `docs/bugs/00_INDEX.md` |
| Where does the code live? | `docs/CODE-MAP.md` |

Git log is the authoritative narrative of what shipped.


## Known limits — recorded, not fixed

These are design and tuning *limits*, not defects. Defects live in
`docs/bugs/`.

- **A sub-cell part's ghost falls back to its footprint cells.** A part that
  flips no cell centre, like a 0.5 m log, still shows its refusal on the coarse
  footprint. A ghost drawn from the brush mesh would be the truthful display.
  *(Added by Claude.)*

- **Construction attach reach is a new tolerance.** A part counts as attached
  within half a lattice diagonal of the brush, plus one cell downward. It
  replaced the footprint rule in `c9430a4`, and placement shifts slightly.
  *(Added by Claude.)*

- **Style budget overruns** reported by the commit hook: `edit_store.cpp`
  (396 lines), `dc_world_preview.gd` (528), `simplex.gd` `minimize()` (55-line
  function), and `test_cell_sample_convention.gd` (471). They don't block;
  they're candidates for pass 2. *(Added by Claude.)*

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
