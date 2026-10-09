# Project Status

> **Who this is for:** Robert. Agents read `CLAUDE.md`.
>
> **Maintenance contract:** the Resumption Brief must reflect the current
> moment. Rewrite it, don't append to it. The Tracker below may drift.
> If updating this doc takes more than ten minutes, it's too big — shrink it.

---

# Resumption Brief

*Last rewritten: 2026-10-09, by Claude, recording the on-hold status.*


## ON HOLD (2026-10-07)

Robert's working energy went to a new venture on 2026-10-07 (ClodForest: `venture-cordial`).
Before that, from 2026-10-04, his focus had moved to CoffeeBEANS. No resume date. Nothing below
is in flight; this is where things stood when they stopped.


## Where things stand

`master` holds everything and is pushed. The last code work was the two overnight sessions of
2026-09-26 and 2026-09-27; since then only docs and the build script changed.

- **Every action lattice runs in C++,** gated bit-exact against the GDScript oracle. A placement
  click costs about 0.7 ms.
- **One matter-changed event per write, carrying its source** (`EditSource`), with measured cell
  flips from every writer.
- **Saves are a consistent pair in a single format,** with PartIndex saved; corrupt saves are
  refused.
- **Doc 22 phase 1 (test instruments) is done:** the headless replay runner
  (`test/support/scenario.gd`), the in-game recorder (`rec` / `mark`), `leaf_info`, named saves.
- **Bugs and features are tracked in GitHub issues** (#1–#23 open, all bugs; the worst are sev:med:
  #4 refine-drain budget, #5 incremental-emit neighbour ring, #15 MPM contact, #19 player burial).
- **Docs since then:** design 23 (thin features, discussion brief), design 24 (L-system trees,
  parked), the known-contradictions register (reference 12), the handoff routine
  (`roadmap/vision/handoff/`). Manifesto #1 and commercial status are marked open.

GUT at last run (2026-09-27): **490 tests, 485 passing, 5 pending, 0 failing.** The pending tests
are gates for filed bugs. Not re-run for this rewrite; no code has changed since.

**Run `tools/build` after pulling.** It now does the class-cache pass itself and refuses while an
editor GUI is open (docs/BUILD.md).


## Next step, on resuming

1. Run `tools/build`, then GUT, and confirm the counts above.
2. Read the morning brief at the bottom of [`overnight-2026-09-27.md`](overnight-2026-09-27.md)
   and answer [`overnight-2026-09-27-questions.md`](overnight-2026-09-27-questions.md) inline.
   Still unreviewed. Top questions: the cell-centre solidity rule, stray-flip protection for every
   writer, whether to post on Godot issue #123700. Then move both to `roadmap/implementation/done/`.
3. Play-test on a GPU using the list in that morning brief.
4. Pick the work from the answers: stray-flip protection, the solidity rule, doc 22 phase 2 (field
   captures), the "compelling, not accurate" rendering design session (reference note 09: the
   badly drawn stones need exact Hermite data, not more refinement).


## Paused threads, one line each

- **Code review pass 2** (Robert reads, `RdF:` comments, Claude applies). Resume with a small leaf
  file (`voxel_constants.gd`, an `actions/*.gd`), then `engine/voxel_dc/` (`dc_octree.h` unread).
  Queued: the `Brush` bundle, internal `TerrainParams` in C++, the name-and-comment sweep,
  `mesh_world` `ViewParams`. Guidance so far: group related params; comments say *why*; no pimpl.
- **Perf:** incremental accel bake (impl doc 17); multithread the mesher (instrument phases first,
  then a `dcthreads` knob, then parallelize the bake and leaf sampling).
- **MPM substrate** (doc 12, verdict GO): fast 3×3 SVD → multithread → GPU → thaw/freeze coupling.
  The SVD rewrite must fix #17.
- **Parts-as-voxels stage 6** (merge-back): parked; it becomes the MPM freeze.
- **Vocabulary sweep** "terrain" → "matter": fold into the name-and-comment sweep.
- **Doc 22 phases 2–3,** then **FEAT089, parts look like parts.**

*Section drafted by Claude.*


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
| What defects are open? | [GitHub issues](https://github.com/rdeforest/voxel-mvp/issues) (`gh issue list --label bug`) |
| Where does the code live? | `docs/CODE-MAP.md` |

Git log is the authoritative narrative of what shipped.


## Known limits — recorded, not fixed

These are design and tuning *limits*, not defects. Defects are
[GitHub issues](https://github.com/rdeforest/voxel-mvp/issues).

- **A sub-cell part's ghost falls back to its footprint cells.** A part that
  flips no cell centre, like a 0.5 m log, still shows its refusal on the coarse
  footprint. A ghost drawn from the brush mesh would be the truthful display.
  *(Added by Claude.)*

- **Construction attach reach is a new tolerance.** A part counts as attached
  within half a lattice diagonal of the brush, plus one cell downward. It
  replaced the footprint rule in `c9430a4`, and placement shifts slightly.
  *(Added by Claude.)*

- **Style budget overruns** reported by the commit hook: `dc_world_preview.gd` (529),
  `player.gd` (431), `console_commands.gd` (402), `dc_octree.h` and
  `dc_octree_mesher.cpp` (long file, several long functions),
  `simplex.gd` `minimize()` (55-line function), and a few long test files. They don't block;
  they're candidates for pass 2. (`edit_store.cpp` is back under budget after the overnight
  split into `edit_store_*.cpp`.) *(Added by Claude.)*

- **Flatten preview z-fights with the surface it's matching.** Cosmetic.
  Cleanest fix is a small forward offset on the preview plane normal.

- **`_resume_unfinished_floods` budget starvation.** Components larger than
  `DETECTION_BUDGET` (500 voxels) take multiple settled frames to fully detect.

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
