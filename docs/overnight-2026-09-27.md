# Overnight session plan — 2026-09-27

*Drafted by Claude. **Approved by Robert 2026-09-26 evening.** It's an operational doc: move it to
`roadmap/implementation/done/` when the session is closed out.*

## Progress

- [ ] E1 — `Mat3` zero-init + MPM conditioning log (Q9)
- [ ] E2 — stamp paint rule matches `materials()` (Q6)
- [ ] E3 — frontier lazy invalidation on edit (Q10)
- [ ] E4 — RAM cell arena with a budget cap; mmap removed (Q4)
- [ ] E5 — C++ solver for the exact thaw carve (Q2, Q3) (stretch)
- [x] G1 — fold the 2026-09-26 answers into the bug files and docs
- [x] G2 — edit events carry their source; raise/lower/flatten emit measured flips (Q1). One
  matter-changed event per write (`terrain_sdf_changed` + `EditSource` + measured `CellFlips`);
  `voxel_added`/`voxel_removed` folded into it. **Behaviour change:** terraforming now releases
  parts from PartIndex and registers its cells in TerrainSupport with their real material; the scout
  now keeps edits made while MPM is in flight (it used to drop them), floods after a console
  `mpmthaw` (INSTRUMENT), seeds from its own thaw's collateral flips (cells the box rewrite
  flipped outside the thawed component; it used to ignore them), and ignores MPM freezes by source,
  including the chunked freeze path (regions over 24 m) it used to react to. The scout already
  flooded after terraforming while MPM was idle; that isn't new. New bug:
  `mpm-freeze-flips-unmeasured` (C++; also blocks the scout hearing freezes).
- [x] G3 — save-pair integrity; single save format (Q5). Shared save id in both halves (snapshot
  v8, blob header v3); temporaries are renamed in only after both read back whole (FileAccess drops
  a failure flushing a file's tail at close); a committed save a crash or failed rename interrupted
  is finished by the next load or F5. Lone, mismatched or older halves are refused and kept.
  **Unilateral:** a refused save still blocks F5 until console `reset` (not moved aside); named
  saves (G4.4) soften that. Q5 left the choice open.
- [ ] G4 — doc 22 phase 1 (headline): gaps, steps, runner, recorder, instruments
- [ ] R1 — research: what the refine frontier spends its effort on + perceptual LOD survey
- [ ] Integration review of the merged result; morning brief at the bottom of this doc

"Q" numbers refer to [`overnight-2026-09-26-questions.md`](roadmap/implementation/done/overnight-2026-09-26-questions.md);
Robert's answers are inline there.

## The constraint that shapes everything

Same as last night: one Godot checkout, one `modules/voxel_dc` symlink, one output binary.

- **Track E owns the C++ build** and works in the main checkout.
- **Tracks G and R are GDScript-only.** Each works in its own worktree and runs GUT against a
  snapshot copy of master's binary, taken at session start. Neither ever calls `tools/build`.

Tracks may not edit each other's files. A chunk that needs another track's file stops and reports
it, and Claude does that piece after the merge.

- **E owns:** `engine/`, `scripts/dc/` (the arena budget and pop-up), `test/test_dc_*`, the C++
  side of any test, and the bug files for E1–E5.
- **G owns:** `scripts/actions/`, `scripts/events/`, `scripts/persistence/`, `scripts/structural/`,
  `scenes/`, `scripts/dc/edit_store_manager.gd` (the save format), `test/support/`, and every other
  bug file and doc.
- **R owns:** only new files under `scripts/dev/` plus one new reference note. It changes no game code.

## Track E — engine, main checkout, branch `fix/engine-2026-09-27`

1. **E1, `Mat3` zero-init + a conditioning log.** Give `Mat3` a zeroing constructor (or zero `u`
   before filling it), which removes the uninitialized read at rank ≤ 1. Add a cheap measurement: the
   smallest σ₂/σ₀ each thaw's particles reach, readable from a test or harness. Gate: the pending
   rank-deficient case no longer reads uninitialized memory (check under a sanitizer build if cheap,
   otherwise by construction), plus a measured number for the morning brief: does real play go
   below 1e-4?
2. **E2, stamp paint rule.** `_stamp_region` UNION paints only where the edit made a corner solid, the
   same as `SdfLattice.materials()`. Test: stamp next to solid terrain of another material; the
   terrain keeps its material. Close `edit-store-stamp-union-repaints-terrain`.
3. **E3, frontier lazy invalidation.** Each frontier entry records its cell's generation; killing or
   regrowing a cell bumps it; a pop skips stale entries; `edit_world` pushes fresh candidates for the
   band it changed. Nothing is cleared wholesale. Gate: a GUT test for budgeted grow → edit →
   reuse-grow that refines no stale cell and reaches the same surface as a fresh build. The existing
   DC tests stay unchanged. Close `dc-edit-world-stale-refine-frontier`.
4. **E4, RAM cell arena with a budget cap.** Replace `MmapArena` with plain RAM storage and a hard
   capacity derived from the development RAM budget (32 GB total; the cells get a stated share, e.g.
   16 GB ≈ 54 M cells at 296 B each). Then:
   - Refinement stops at the cap, generalising the existing `max_cells` gate, with a loud message at
     the cap rather than a crash.
   - **Growth must not copy a multi-gigabyte array.** Use chunked blocks or reserve capacity once,
     portably (Linux, macOS, Windows), and measure.
   - Remove the mmap code, the temp-dir probing, the fallback pop-up, `DC_ARENA_FAIL_DISK_MMAP` and
     its test.
   - Delete `mmap-arena-disk-full-sigbus`; the mechanism is gone.
   - Gate: existing DC tests unchanged, and grow timings measured before and after with no
     regression.
5. **E5 (stretch), exact thaw carve solver.** A C++ `EditStore` method that chooses corner values so
   every planned cell ends past zero toward air, every kept cell stays solid, and every unplanned cell
   keeps its side, each by a margin. It's the `StoreWrite.one_cell` linear program generalised, sized
   for thousands of cells. It reports infeasibility instead of shrinking the plan. Tested by itself
   in GUT. **Wiring it into `MpmStructure` is not in this track** (that's G's file); it's a follow-up
   after the merge.

## Track G — game logic, worktree, branch `feat/instruments-and-events`

1. **G1, housekeeping.**
   - Fold Robert's answers into the bug files: record each decision, close Q8 and Q14, re-scope Q7
     (moves to assembly-path identity), Q11 (deprioritised), and Q12 and Q13 (accepted; document
     `changed` as "some sample moved").
   - Update `04-event-bus.md`'s "Lifetime & cleanup" section (Q15).
   - Correct the 2026-09-26 brief's stale "nothing pushed" note.
   - Move `overnight-2026-09-26.md` and its questions doc to `roadmap/implementation/done/`.
2. **G2, edit events carry their source.**
   - Every edit event says who made it (player, instrument, MPM, scout, replay).
   - A single "matter changed" event carries the measured flips and the source.
   - Raise, lower and flatten emit their measured flips (`StoreWrite.reshape` returns what the write
     measured), so PartIndex, support and detachment hear terraforming.
   - DetachmentScout ignores MPM's own edits by source instead of by timing.
   - Tests: flatten through a placed part releases its record; a thaw that empties nothing doesn't
     make the scout re-flood.
   - Close `actions-reshape-no-voxel-events`.
   - Behaviour change to record in the brief: support and detachment now react to terraforming.
3. **G3, save-pair integrity.**
   - A shared save id in both files, and an atomic pair write (temp names, then rename).
   - Refuse and keep a lone or mismatched half.
   - Drop the pre-S4 snapshot-only compatibility.
   - `refusal()` accepts only the current `SAVE_VERSION`, removing J1's v1 read path.
   - Tests for each case, failing on the old code. Close `save-pair-consistency`.
4. **G4, doc 22 phase 1**, in chunks, each shipping on its own:
   - **G4.0, gaps first.**
     - PartIndex is saved and restored with the world.
     - DetachmentScout's pending work counts in `is_quiescent()`.
     - MPM's freeze order is deterministic by position; the camera only prioritises meshing.
   - **G4.1, serializable steps.**
     - `to_step()` on each Action, and a registry that rebuilds an action from a step.
     - A CSG shape rebuilt from kind + dims; a Part recorded by path + dimensions.
     - Steps are JSON written with `full_precision`, gated on a round-trip test proving doubles
       survive exactly.
   - **G4.2, replay runner** (`test/support/scenario.gd`).
     - A headless world: store, structural systems, PartIndex, MPM, scout, a player stub.
     - Simulations tick explicitly at 1/60 s; this needs tick seams on DetachmentScout and
       StructuralIntegrity.
     - Stops at the first step whose `validate()` differs from the recording.
     - A GDScript builder API that writes and reads the same JSON.
   - **G4.3, recorder.**
     - A hook at `player.gd`'s validate/execute site.
     - `rec start` (waits for a settled world) / `rec fresh` / `rec stop`.
     - `mark [note]`: camera, FOV, dcworld settings, aimed cell with its probe report, and a
       screenshot.
     - `mpmthaw` is recorded as a step.
     - Scenario directories under `user://scenarios/<name>/`.
   - **G4.4, instrument layer.**
     - The probe also reports leaf, size, field state, 8 corners and the mesher's sign test.
     - Exact console writes: set a cell's corners, set a material, stamp a typed CSG shape by
       numbers. They go through the normal write path, bypass player safety, and switch to fly
       mode when the write would bury the player or drop them.
     - Named saves: `save <name>` / `load <name>`.

   Each G4 chunk has GUT coverage. The recorder and instruments get a replay test: record steps
   headlessly through the runner's builder, replay them, and get the same store.

## Track R — research, worktree, branch `research/perceptual-lod`

1. **R1, where the refinement budget goes, and what else is possible.**
   - A headless harness in `scripts/dev/` builds an edited scene on the real field (a few placed
     stone blocks, the "mini-stonehenge", beside smooth generator terrain and a distant ridge).
   - It runs the live `grow_world` path and reports what the frontier holds: distance, edited vs.
     generator cells, surface curvature, and screen error.
   - Plus a sourced prior-art survey: feature-aware and perceptual LOD metrics, curvature and
     silhouette weighting, and detail faked by shaders (normal and parallax techniques on
     SDF-derived meshes).
   - **Deliverable:** `docs/roadmap/reference/09-perceptual-lod-research.md`. Evidence and options
     for Robert's "compelling, not accurate" design session. **No mesher changes.**

## The review loop, per chunk

Unchanged from last night:
- An Opus 5.5 author.
- An Opus 5.5 correctness reviewer and a Sonnet 5 completeness reviewer, in parallel and adversarial,
  seeing only the diff, the bug file and the files it names.
- A separate agent for any question a reviewer can't answer.
- A Fable 5.1 tiebreak when a blocking issue is disputed.
- An Opus 5.5 fixer who commits only on green GUT and explains any change in the counts.

Track R is research: one author and one skeptical reviewer, no fixer.

**After the tracks merge:** an integration review of the combined result, the step that caught real
cross-track bugs last night, then a holistic review of whatever the most-touched subsystem turns out
to be.

## Standing rules for the session

- Nothing else runs. The Godot editor GUI stays closed.
- After any pull or new `class_name`: the class-cache pass (`bin/godot --path . --headless --editor --quit`).
- Fixed bug: delete the file and its index row (the `00_INDEX.md` rule).
- Don't scope-reduce a chunk to close it. If the hard part is cut, say so in the brief.
- Where a question genuinely needs Robert's judgement, record it with evidence in the brief and move
  on. Don't guess his intent and build on the guess.
- Anything decided unilaterally goes in the brief so he can overrule it.
- Development budgets: 32 GB RAM, 32 GB disk, 32 GB VRAM. Fail loudly at them.
- Portable mechanisms only (Linux, macOS, Windows) unless there's a stated reason.

## Session facts (survive a restart)

- **Pushes:** this session may be started remotely, so the ssh-agent can be dead. Always push with
  `GIT_SSH_COMMAND='ssh -o IdentitiesOnly=yes -i ~/.ssh/id_rsa'`. Remote start also means no
  `DISPLAY`, which doesn't matter for headless work.
- **Claude Code:** the stable-channel auto-updater points `~/.local/bin/claude` back at 2.1.274, which
  can't run Opus 5.5. A running session is unaffected; a relaunch needs `claude install 2.1.283` (or
  later) first.
- **GUT baseline** on master `08111ec`: **318 tests, 314 passing, 4 pending, 0 failing**
  (`tmp/gut-pre27.log`). Any change to those counts needs an explanation.
- The snapshot binary for Tracks G and R is copied from master's build at session start and never
  rebuilt. Track E's rebuilds can't disturb their tests, because they run a separate copy.

## Autonomy expectation

Robert is asleep for about eight hours. Work the whole window; don't stop and wait.
- Commit the smallest self-contained chunks that pass tests, and push after each merge.
- Start extra agents or workflows purely to answer questions the agents raise, so nothing blocks on
  Robert.
- Past instincts (Robert's, recorded in old docs and memory) are open to reconsideration. Only the
  manifesto's principles and the vision are fixed.

## Morning brief

*Filled in at the end of the session: decisions made unilaterally, open questions, what got skipped and
why, and a short play-test list.*
