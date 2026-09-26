# Overnight session plan — 2026-09-26

*Drafted by Claude, approved by Robert before sleeping. Operational doc: delete
or move to `docs/completed/` when the session is closed out.*

## Progress

- [ ] Track A1 — preview lattice in C++ (`actions-preview-gdscript-slow`)
- [ ] Track A2 — `sdf-lattice-writes-false-change-at-max-faces`
- [ ] Track A3 — `mmap-arena-no-mmap-fallback` (if time)
- [x] Track B1 — characterize `single-voxel-edits-unexpected`
- [ ] Track B2 — `empty-voxel-no-player-safety`
- [ ] Track B3 — `part-index-footprint-cells-never-released`
- [ ] Track B4 — `mpm-thaw-events-unmeasured`
- [ ] Track B5 — MPM SVD regression test (if time)
- [ ] Morning brief + play-test list at the bottom of this doc

## The constraint that shapes everything

One Godot checkout, one `modules/voxel_dc` symlink, one output binary. Two
tracks compiling at once corrupt each other, and a track running GUT could be
testing a binary holding the other track's half-finished C++. Worktrees do not
help: the engine anchor resolves to the main checkout by design.

Therefore **Track A owns C++ and the build. Track B is GDScript-only and runs
GUT against a snapshot copy of the binary.** Track B never calls `tools/build`.

## Track A — engine, main checkout, branch `perf/preview-lattice-cpp`

1. `actions-preview-gdscript-slow` — build the lattice and flip set in C++ as an
   `EditStore` method. Gate: byte-identical against the GDScript `SdfLattice`
   on a faithful multi-level field (not a raw analytic one), plus re-measured
   preview ms at or below the bug file's "before" column.
2. `sdf-lattice-writes-false-change-at-max-faces` — same code, now in C++.
3. `mmap-arena-no-mmap-fallback` — small, contained.

## Track B — GDScript only, worktree, branch `fix/single-voxel-and-action-bugs`

1. Characterize `single-voxel-edits-unexpected`. Harness in `scripts/dev/`.
   Deliverable is evidence, not a fix: what the LP intended, what the mesher
   produced, how far off-centre, how often it refused. Ends in a question for
   Robert.
2. `empty-voxel-no-player-safety`
3. `part-index-footprint-cells-never-released`
4. `mpm-thaw-events-unmeasured`
5. MPM SVD regression test (`det(U)·det(V)`, `sign(σ₂)`) before the fast-SVD
   rewrite.

Track B stays off `sdf_lattice.gd` and `store_write.gd` so it cannot collide
with Track A.

## The review loop, per chunk

Author → correctness reviewer + completeness reviewer (parallel, adversarial)
→ fixer. GUT gates every step; report counts. Baseline is 192 tests, 190
passing, 2 pending, 0 failing.

- **Reviewers see the diff only**, plus the bug file and the named files. No
  whole-header reads for context. A reviewer who needs information it does not
  have passes the uncertainty up rather than going to find it; Claude resolves
  it, spawning a flow to answer the question if that keeps work moving.
- Models (if the CLI is ≥ 2.1.280): author, correctness reviewer and fixer on
  Opus 5.5; completeness reviewer on Sonnet 5 — a different family, because
  identical models make correlated mistakes. Fable 5.1 only as a tiebreak when
  the reviewers materially disagree.
- **Commit small.** Smallest self-contained chunk that passes tests, committed
  when tests are good and green. Robert is reading these.

## Standing rules for the session

- Nothing else runs on the machine. The Godot editor GUI stays closed.
- After any pull or class-hierarchy change: the class-cache pass
  (`bin/godot --path . --headless --editor --quit`). See `docs/BUILD.md`.
- Enter the repo physically (`cd -P`) or through either spelling now that
  `tools/lib.sh` resolves the root physically.
- Do not scope-reduce a chunk to close it. If the hard part is being cut, say
  so in the brief instead.

## Autonomy expectation

Robert is asleep for roughly eight hours from 2026-09-25 late evening. He is not
available to unblock anything. Work the whole window; do not stop and wait.

- A reviewer that raises a question it cannot answer from its packet passes the
  uncertainty up. Resolve it yourself — including by starting a flow whose only
  job is to answer that question — rather than parking the chunk.
- Where a question genuinely needs Robert's judgement (what something should
  *look* like, what he expected to happen), record it in the morning brief with
  the evidence gathered so far and move to the next chunk. Do not guess his
  intent and build on the guess.
- Anything decided unilaterally goes in the morning brief so he can overrule it.

## Session facts (survive a restart)

- Claude Code is **2.1.283** (installed from the `latest` channel; `stable` was
  2.1.274 and does not know Opus 5.5, which needs >= 2.1.280). `autoUpdatesChannel`
  is left on `stable` deliberately, so the version is pinned, not tracking.
- Robert relaunches with `claude --model 'claude-opus-5-5[1m]'`. Both that and
  the plain id were probe-tested on this machine.
- Confirm that the Agent/Workflow `model: "opus"` alias resolves to 5.5 in this
  build before launching the workflows. If it still resolves to Opus 5, name the
  model explicitly wherever the workflow API allows it.
- GUT baseline on master at `9fe188b`: **192 tests, 190 passing, 2 pending, 0
  failing** (`tmp/gut-after-cache.log`). Any change to those counts needs an
  explanation.
- `tools/build` and `bin/godot` now work from either path spelling, so `cd -P` is
  no longer required.

## Morning brief

*Filled in at the end of the session: decisions made unilaterally, open
questions, what got skipped and why, and a short play-test list.*
