# Overnight session plan — 2026-09-27

*Drafted by Claude. **Approved by Robert 2026-09-26 evening.** It's an operational doc: move it to
`roadmap/implementation/done/` when the session is closed out.*

## Progress

- [x] E1 — `Mat3` zero-init + MPM conditioning log (Q9)
- [x] E2 — stamp paint rule matches `materials()` (Q6)
- [x] E3 — frontier lazy invalidation on edit (Q10)
- [x] E4 — RAM cell arena with a budget cap; mmap removed (Q4)
- [x] E5 — C++ solver for the exact thaw carve (Q2, Q3) (stretch)
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
- [x] G4 — doc 22 phase 1 (headline): gaps, steps, runner, recorder, instruments. G4.0–G4.4 done, and F2 finished G4.4's leaf read-out. Not built: the probe overlay, which waits on Robert (question 22), and assembly export/import, which is doc 22 phase 3.
  - [x] G4.0 — gaps: PartIndex saved (snapshot v9, bit-exact bytes; a snapshot whose parts break
    one-owner/unique-id is refused); scout pending work and MPM's unannounced freeze chunks gate
    `is_quiescent()`; MPM freeze chunks announced bottom-up by position, appended (a second freeze
    no longer drops the first's). **Unilateral:** camera-nearest re-meshing of big freezes dropped
    (only separable inside DcWorldPreview, Track E's); dead `MpmStructure.reset()` removed.
    **Found:** `var_to_str` and JSON `full_precision` don't round-trip ~31%/~24% of doubles on this
    engine; G4.1's step format needs an exact number encoding.
  - [x] G4.1 — serializable steps: `to_step()`/`from_step()` on every action, `StepRegistry`,
    `StepDocument` (format/version/units header, a step per line), exact JSON numbers
    (`StepJson`/`ExactDecimal`: the engine's writer is exact, its reader isn't, so numbers are
    re-read from their text with correct rounding; `-0.0` keeps its sign; any duplicate key is
    refused, after review found one that silently swapped numbers). **Unilateral:** a part
    with no file is recorded whole by its dimensions; flatten records the normal as given (a third
    of unit normals move an ulp on renormalizing); unit strings deferred to the phase-3 evaluator.
  - [x] G4.2 — replay runner + builder (`test/support/scenario.gd`): a headless world (store,
    support, PartIndex, MPM, scout, player stub) whose sims tick only through `advance(n)`/`settle()`
    at 1/60 s, in the live frame order; `tick()` seams on DetachmentScout and StructuralIntegrity.
    Builder calls write a step, read it back from its JSON and run that, so builder and replay are
    one path; a replay stops at the first step whose `validate()` differs (or that won't decode or
    settle) and names its index. World steps (`player_at`, `advance`, `settle`, `mark`, `thaw`) are
    encoded in `StepRegistry`. **Found and fixed:** the snapshot stored tracked support and the
    player as `var_to_str` text, so a world loaded from a save was an ulp off (a replay from the pair
    diverged in `capture()`); they are bytes now, snapshot v10. **Unilateral:** a scenario starts
    from a save *pair* (`start_save`), not a lone blob: a blob alone drops part identity and
    tracked support, the gaps G4.0 closed. One scenario is live at a time, because the event bus
    is global and its events carry no world.
  - [x] G4.3 — recorder: `Player.action_validated` (emitted between `validate()` and `execute()`
    in `_try_edit_terrain`) feeds `ScenarioRecorder`; `RecordingCommands` (a World child) adds
    console `rec start|fresh|stop [name]` and `mark [note]`; `mpmthaw` and console `settle` are
    steps too (`thaw`, new `drain_support`). A directory under `user://scenarios/<name>/` holds
    `steps.json` (rewritten per step, so a crash keeps what came before), the start's save pair
    (`rec start`, gated on `is_quiescent()`), and `mark-NNN.json`/`.png`. The runner's
    `run_recording(dir)` replays one; `capture()` now includes MPM's in-flight particles.
    Verified live (headless World scene, `scripts/dev/probe_recorder_live.gd`): `rec fresh` and
    `rec start` recordings with digs, a refused fill and a mark replay byte-identical in field,
    parts, support and MPM; but MPM was empty and support drained at both stops, so the live
    check proves the edits and step round-trip, not frame alignment. Frame alignment is covered by
    GUT (one frame fewer, or one frame moved from after the cut to before it, replays to a
    different world). **Debt:** `steps.json` is re-serialized whole per step (O(n) per step, O(n²)
    per recording); fine at play-session sizes, revisit (append-only) if recordings get long.
    **Found:** the console pauses the tree (`pause_when_open`), so the
    engine's physics frame count keeps running while the simulations don't; the recorder counts
    its own unpaused physics frames (measured: 10 paused frames, clock +0, engine +10).
    **Unilateral:** frame and player position are encoded as `advance`/`player_at` steps (the
    runner's strict decoding refuses extra fields on an action step); `rec fresh` resets the live
    world (like `reset`) and starts on the reloaded world's first frame; `mark` needs a live
    recording; a name defaults to the date-time; an existing directory is refused. **Not verified
    live:** `mpmthaw`'s step (the console aims with the physics raycast, which never hit terrain
    in the headless World; covered in GUT) and the screenshot (headless has no rendered viewport).
  - [x] G4.4 — instrument layer (leaf read-out completed by F2): the probe adds edited/generator leaf, the 8 corners
    the mesher samples, its sign test and seams; console `setcorners`/`setmaterial`/`stamp` write
    exactly (ExactDecimal) through StoreWrite/VoxelImprint as INSTRUMENT, recorded as steps
    (`set_corners`/`set_material`/`stamp`); a write that buries the player or drops their ground
    puts them in fly (noclip when buried); `save <name>`/`load <name>` slots under
    `user://saves/<name>/`. Tested through LimboConsole's own dispatcher. **Not built:** the
    leaf/sign overlay (visual, question for Robert), assembly export/import (phase 3).
- [x] R1 — research: what the refine frontier spends its effort on + perceptual LOD survey.
  Headline: the stones never enter the frontier. Their error comes from the 1 m scalar
  reconstruction (linear crossings, h = 1 m normals); exact Hermite data fixes it at 1 m cost. The
  drain refines already-under-eps cells to the floor (0.47 M → 3.46 M cells for +13% triangles).
  Doc `reference/09`.
- [x] Integration review of the merged result (7 real findings, all small; fixed in F4)
- [x] F4 — integration-review fixes + dev-harness parse check (follow-up, after the merge):
  `test_dev_harnesses_parse` compiles every `scripts/dev/*.gd` (failed on the stale MPM probe, now
  fixed); `dcmaxcells` help/status built from the capacity, reports live cells vs slots, `0`
  restores the default (C++ `get_octree_live_cell_count`); DcWorldPreview `cell_limit()` /
  `cell_stats()` shared by the status line, recorder marks and `/stats`, which skips mesher fields
  mid-job; dangling bug links, extras-11 pointer, GLOSSARY
- [x] F1 — wire the exact carve (`predict_carve`) into the MPM thaw (follow-up): `thaw_cells` writes
  the solved lattice (r=3 / r=5 spheres empty 63/63 and 176/176, a lone buried cell empties, zero
  stray flips); a refused carve refuses the whole thaw (push_error + `thaw_refused` → Toast); the
  conditioning gauge resets per thaw. Bug closed; design in doc 12 "The thaw carve"
- [x] F2 — `EditStore.leaf_info` binding; probe shows the owning leaf (completes G4.4) (follow-up):
  `leaf_info(p)` = { origin, size, field (`EditStore.FieldState`, now bound), corners } + material
  (edited) + source_origin/size (inherited); the probe prints the leaf's state, size and origin, and
  an inherited leaf's source. GUT on the real store: generator root, own-field, inherited next to a
  finer write (its stored corners = float32 of what the store reads there), unedited sibling. Overlay
  not built. Filed edit-store-blob-inherited-corners-unchecked (load never checks those stored corners)
- [x] F3 — the MPM freeze reports its measured flips (follow-up): `rasterize_to_store` writes via
  `write_region_flips` (+0.5 ms on the 674- and 729-cell freezes, 3.6→4.1 / 6.7→7.3 ms); a chunked
  freeze gives each chunk the flips inside its box (**unilateral**); TerrainSupport's phantom branch
  kept as a check. Part (3), scout seeding from freeze flips, NOT enabled: the probe found a loop (a
  voxel on a 1 m grid post froze and was thawed 8 times), so per the brief the scout still ignores
  freezes; re-scoped to scout-ignores-freeze-flips. Also filed mpm-chunked-freeze-flips-arrive-late
  (a stale chunk flip releases a live part, pending test). Design in doc 12 "The freeze (as built)"
- [x] F5 — tests use per-process user:// paths (no more XDG_DATA_HOME needed for parallel GUT)
- [x] Morning brief at the bottom of this doc

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

*Drafted by Claude at the end of the session. Everything is merged to `master` and pushed.*

### Needs you first

Answer inline in [`overnight-2026-09-27-questions.md`](overnight-2026-09-27-questions.md). The top
four:
1. **Post our findings on Godot's float-parsing issue #123700?** A draft comment is in the
   questions doc. Posting is outward-facing, so I didn't.
2. **A grid-aligned 1 m post renders and collides, but the structural code sees air.** This is the
   cell-centre solidity rule again, the one behind your single-voxel surprise. It blocks the scout
   from reacting to freezes. It needs a short design discussion.
3. **Should every box writer keep unplanned cells on their side,** as the thaw now does?
4. **Look at carved walls and stamp paint on a GPU.** See the play-test list below.

The other 20 questions are small, and most have a recommendation you can answer with "yes".

### What landed

All 5 tracks and 18 chunks, in 20 commits:
- **Engine:** the SVD rank fix; stamps paint only what they made; lazy frontier invalidation; a RAM
  cell arena capped at 16 GiB with mmap gone (builds about 30 % faster); the exact thaw carve,
  wired in (spheres now empty 63/63 and 176/176 planned cells, the 729-cell block thaws in 2.9 ms
  instead of 5.2 ms, with zero stray flips).
- **Game:**
  - One matter-changed event per write, carrying its source, so terraforming now reaches PartIndex
    and support.
  - Consistent save pairs in a single format, with PartIndex saved.
  - Doc 22 phase 1: exact serializable steps, a headless replay runner, the in-game recorder
    (`rec` / `mark`), and the instrument layer (probe with leaf info, exact console writes, fly
    rescue, named saves).
- **Follow-ups after the merge:**
  - Freezes report measured flips (+0.5 ms per freeze).
  - `leaf_info` for the probe.
  - The integration review's fixes.
  - A GUT test that fails if any `scripts/dev/` harness stops compiling.
- **Research:** reference note 09. The stones you saw badly drawn weren't waiting for refinement.
  They sit at the 1 m floor, and the damage is surface reconstruction. Exact surface (Hermite) data
  at 1 m would fix them at no extra cell cost. Seven options, none chosen, for your "compelling,
  not accurate" session.

GUT went from 318 tests / 314 passing / 4 pending to **484 / 479 / 5**, with 0 failing throughout.
The new pending test is the gate for `scout-ignores-freeze-flips`.

### Decided without you, overrule freely

- **Carve policy:** an infeasible thaw plan is refused whole and loudly (0 of 25,600 realistic
  plans refused). The solve aims for a clean carve at the boundary with kept terrain, not the
  smallest change to corners.
- **Freeze events:** a chunked freeze gives each chunk event the flips inside its box. The scout
  still ignores freezes, because enabling it loops (question 2).
- **Behaviour changes to know about:**
  - Terraforming releases parts and registers support with the real material.
  - A console `mpmthaw` counts as an instrument edit, so detachment follows it.
  - A part whose support is flattened away falls rather than sags (question 14).
- **Saves:** an unreadable save still blocks F5 until `reset` (named saves soften that). The
  snapshot's floats are stored as bytes (v10), because Godot's float parser loses an ulp.
- **Steps:** our own exact number reader (`ExactDecimal`) works around the parser. Steps are in
  metres; units come with the phase 3 evaluator.
- **Engine:** no zeroing `Mat3` constructor (1.5 % cost; the defect is fixed at its cause).
  `max_cells 0` now means "capacity". `sizeof(Cell)` is pinned by an assert, because a larger
  layout measured 15–25 % slower.
- **Tests and parallel runs:** tests write fixed `user://` file names, so parallel GUT runs
  collided. Every track ran with its own `XDG_DATA_HOME`. **Not fixed at the source:** tests should
  use unique temp names.
- **Bug records:** two "not a bug" verdicts (`edit-store-noop-write-reports-changed`,
  `dig-action-no-validate-no-safety`) went to `closed/`. Everything fixed was deleted.

### Not done, and why

- **The probe overlay:** it's visual, and what it looks like is your call (question 22).
- **Scout seeding from freezes:** it loops (question 2).
- **Stray-flip protection for the other writers:** waiting on question 3.
- **A per-process cell counter, the unexplained 12 % drain slowdown, and the MPM friction slide:**
  queued pending your answers (questions 6–8).
- **Nothing was checked on a GPU.**

### Environment

- Pushes worked all night with `GIT_SSH_COMMAND='ssh -o IdentitiesOnly=yes -i ~/.ssh/id_rsa'`.
- The main checkout is back on `master`, and the worktrees are removed.

### Play-test list

1. `mpmthaw 3` and `mpmthaw 5` into a hillside: the whole planned volume should come out. Look at
   the carved wall and the debris.
2. `stamp` (console) a box next to a different material: only the new solid takes the new
   material.
3. Place a beam on a slope, then flatten under it: it detaches and falls. `parts` drops its record.
4. Probe a cell: leaf origin, size, field state, 8 corners and the sign test.
5. `save test1`, change things, `load test1`. Truncate a copy of a save and load it: you get a loud
   refusal, and the file is untouched.
6. `rec fresh`, do a few edits and a `mark note`, then `rec stop`. Look in
   `user://scenarios/<name>/`.
7. `dcmaxcells`: the help quotes the capacity, and the status line shows live cells.
8. Aim previews and place beams: still smooth (a regression check on last night's work).
