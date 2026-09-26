# Overnight session plan — 2026-09-26

*Drafted by Claude, approved by Robert before sleeping. Operational doc: delete
or move to `docs/completed/` when the session is closed out.*

## Progress

- [x] Track A1 — preview lattice in C++ (`actions-preview-gdscript-slow`) — A1a (C++ prediction + byte-identical gate) and A1b (callers switched, `_compute_work` + `_turns_in` ported, re-measured under "before"); bug closed
- [x] Track A2 — `sdf-lattice-writes-false-change-at-max-faces` — flag now "changes a stored float32 corner": owner-leaf reads at max faces, float32 compare, and a dry run for seams/finer leaves; bug closed
- [x] Track A3 — `mmap-arena-no-mmap-fallback` — disk mmap failure falls through to the next dir, then anon; fd closed; hook-driven test. SIGBUS-on-full-disk split to `mmap-arena-disk-full-sigbus` (needs a policy call)
- [x] Track A4 (follow-up) — lattice dry-run worst case — generator and array read once per lattice point; buried refused preview 0.68 → 0.34 ms (dry run 0.47 → 0.126); no change to the answer
- [x] Track B1 — characterize `single-voxel-edits-unexpected`
- [x] Track B2 — `empty-voxel-no-player-safety` (Dig: empty-carve refusal only; its player-safety guard needs `preview()`, specified in its bug file)
- [x] Track B3 — `part-index-footprint-cells-never-released` (sub-cell parts now get no record; filed `part-index-sub-cell-parts-untracked`)
- [x] Track B4 — `mpm-thaw-events-unmeasured` (particles now follow the measured flips too; filed `mpm-thaw-carve-leaves-planned-cells`)
- [x] Track B5 — MPM SVD regression test (all four rows pinned; filed `mpm-svd-ill-conditioned-u`)
- [x] Track D1 (follow-up) — MPM thaw builds its StoreWrite lattice once (`StoreWrite.write` takes the measured lattice; FillVoxel/EmptyVoxel too) — 729-cell block thaw 9.4 → 7.4 ms median, pre-B4 `mpm_structure.gd` on the pre-D1 `StoreWrite` 7.85 ms, on D1's `StoreWrite` 7.6–8.0 ms (same harness, same engine)
- [x] Track E1 (follow-up) — `SdfLattice.materials()` reads "before" from the owner leaf, like the C++ builders — one `SdfLattice.owner_centre` shared with the test oracle; a max-face seam no longer repaints the leaves below it (fill and imprint pinned in `test_lattice_materials`; filed `edit-store-stamp-union-repaints-terrain`)
- [x] Track F1 (follow-up) — `event-bus-reentrancy` — emit snapshots the channel-wide list and every matched cell list before any handler runs, dispatches from the snapshots and prunes the live lists after; unsubscribe cancels a subscription in flight; nested emits stay synchronous. Twelve reentrancy tests, nine fail on the old bus; bug closed
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

Items recorded during the session (to fold into the brief):

- **Behaviour change (B3):** a part that flips no cell centre (e.g. a 0.5 m log
  lying between cell-centre planes) now gets no PartIndex record at all. Before,
  it got an AABB-footprint record nothing could ever release. Only runtime
  consumer is the console `parts` count. Open design question in
  `docs/bugs/part-index-sub-cell-parts-untracked.md`.
- **Convention conflict:** `docs/bugs/00_INDEX.md` says a fixed bug's file is
  deleted and `closed/` is for not-a-bug/obsolete. Track B follows that; Track A
  archived fixed bugs to `closed/` with "fixed" verdicts. Pick one.
- **Behaviour change (B4):** an MPM thaw now seeds particles only for cells the carve actually
  emptied, not every planned cell. Before, planned cells the carve couldn't empty were in the store
  and in the sim at once (a terrain `mpmthaw` r=5: 176 planned, 143 emptied, 33 duplicated). The
  thaw is about 30 % slower (729-cell floating block: 8.8 -> 11.1 ms, once per thaw) because it
  builds the StoreWrite lattice twice; `StoreWrite.cells` taking a prebuilt lattice would remove
  that, but `store_write.gd` is Track A's file tonight. Cells the box rewrite empties outside the
  plan also become particles now, so a thaw can drop debris a few metres from where it was aimed
  (seen: 3 m outside a r=1.4 sphere).
- **Finding (D1):** the double lattice build was not most of B4's slowdown. Profiled on the 729-cell
  block: the second `predict_work` cost ~0.25 ms of the ~1.5 ms; the rest is the measurement itself
  (`lat.cells()` 0.1, `snapshot` 0.44, `since` 0.62 ms of per-cell `store.sample` calls). D1 builds
  the lattice once, reads `StoreWrite`'s current materials with one `fill_indices_region` call
  (0.49 → ~0.03 ms; identical on 270 lattices over a multi-level, multi-material field; `test_store_write.gd` pins it on work, bell and flatten lattices, and an off-grid lattice is refused with an error rather than asserted), and probes
  each kept cell once in the thaw's corner carve (3.7 → 2.1 ms; identical work on 9 test plans).
  Thaw: 9.4 → 7.4 ms (pre-B4: 7.85). The last two speed up code pre-B4 also ran, so the
  measurement still costs ~1.2 ms over an unmeasured thaw; a C++ batch sample would remove it.
- **Question (B4):** a thaw plan the 1 m corner carve can't realize (a lone buried cell, the shell
  of a sphere in solid ground): refuse it, reshape it, or solve for corners that carve it exactly?
  Evidence in `docs/bugs/mpm-thaw-carve-leaves-planned-cells.md`.
- **Finding (B5):** `Mat3::svd` holds the signed-SVD convention in all four reflection rows (now
  pinned by `test/test_mpm_svd.gd`), but U stops being a rotation as F nears singular: det U = 0.93
  at σ₂/σ₀ = 1e-8, 0.16 at 1e-9, 0 at rank ≤ 1 (an uninitialized read). Filed
  `docs/bugs/mpm-svd-ill-conditioned-u.md` with a pending test for the fast-SVD rewrite to turn on.
  Whether the sim ever gets there is unmeasured.
