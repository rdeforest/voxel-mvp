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
- [x] Track C1 (follow-up) — ConstructionAction._attached ported to C++ (`EditStore.imprint_near_solid`); GDScript original to the oracle; gate `test_construction_attach_predict` (placements, lift/side boundaries bisected to adjacent doubles, exact ties). Beam preview, no player: resting 0.326 → 0.144 ms, floating +3 m 0.890 → 0.154 ms (attach scan itself 0.005 / 0.015 ms). Now dominated by `predict_imprint` (~0.067 ms) + `lattice_flips` (~0.064 ms) over the 13³ lattice
- [x] Track C2 (follow-up) — `VoxelImprint.apply` returns its measured `CellFlips`; ConstructionAction registers the part from `.solid` and drops its own snapshot (one measurement per placement). Beam execute() on the game store 7.5 → 6.1 ms (`scripts/dev/bench_construction_execute.gd`). What remains is `SdfLattice.materials` (~4.4 ms: a GDScript Callable per lattice point, 13³) and `CellFlips.snapshot`/`since` (~0.57 / 0.72 ms over 1728 cells); filed `actions-imprint-materials-gdscript-per-point`
- [x] Track G1 (follow-up) — Paint lattice materials in C++ — the brush builders record per point whether the write made it solid (`made`), `EditStore.lattice_materials` paints from it; GDScript original to the oracle; gate `test_lattice_materials_predict` (sphere stamp + 7 imprint shapes unrotated and under 3 turns, both ops, 5 materials and the carve, both air rules, on the multi-level predict store) and a max-face seam on each axis in `test_lattice_materials`; C++ mutations caught but float32-vs-double solidity (unreachable, see the test header); the oracle's implied "or was air before" clause is dropped from the C++, the gate showing the rules agree. `SdfLattice.materials` 4.3 → 0.036 ms; execute() beam 6.3 → 1.8 ms, CSG box ADD 6.6 → 1.8 / SUBTRACT 5.5 → 1.8 ms, fill r2 1.33 → 0.38 ms, dig r2 1.15 → 0.36 ms. `actions-imprint-materials-gdscript-per-point` fixed (deleted); its second option, the ~1.3 ms of `CellFlips.snapshot`/`since`, split to `actions-write-flips-gdscript-snapshot`
- [x] Track G2 (follow-up) — Measure a write's cell flips in C++ — `SdfLattice.write` returns the flips it measured (`EditStore.write_region_flips`: each rewritten cell's sample just before and after `write_region`, z-y-x order, plus each emptied cell's pre-write material and `changed`); every `CellFlips.snapshot`/`since` user routed through it (VoxelImprint.apply, Fill, Dig, `StoreWrite.write` → FillVoxel / EmptyVoxel / MPM thaw, which drops `_solid_materials` / `_changed`). Chosen over a batch `sample_cells` because that leaves ~0.33 ms of GDScript dictionary/compare per 1728 cells (measured floor) plus `cells()`; one C++ pass shares `rewritten_cells` and the flip rule with `lattice_flips`. GDScript measurement to the oracle; gate `test_lattice_write_flips` (sphere stamps, 4 imprint shapes under turns, thaw carves, single-voxel fills/empties, an exactly-zero cell; each written twice so `changed` is compared both ways; lists, order, materials, `changed` and the resulting store) with 7 C++ mutations caught (one equivalent on the 1 m grid, see header). execute(): beam 1.77 → 0.70 ms, CSG 1.74–1.78 → 0.68–0.72 ms, fill r2 0.39 → 0.16, dig r2 0.37 → 0.14; 729-cell block thaw 7.15 → 5.97 ms median of 7. `actions-write-flips-gdscript-snapshot` fixed (deleted). A lattice EditStore refuses writes and measures nothing (empty CellFlips) rather than aborting the writer on the empty result; gated by `test_refused_lattice_writes_nothing`
- [x] Track F1 (follow-up) — `event-bus-reentrancy` — emit snapshots the channel-wide list and every matched cell list before any handler runs, dispatches from the snapshots and prunes the live lists after; unsubscribe cancels a subscription in flight; nested emits stay synchronous. Twelve reentrancy tests, nine fail on the old bus; bug closed
- [x] Track F2 (follow-up) — `save-honesty-gaps` — `force_quiescent` returns whether it drained and push_errors at its pass limit; `settle` says so (F5 never called it — it gates on `is_quiescent` and already refused). The snapshot + EditStore blob load as one `SavedWorld`: a half this build can't read (blob version bump, newer snapshot, foreign blob) refuses the pair with a push_error + Toast, applies neither half, and F5 refuses to overwrite it; `save_to`'s Error is no longer ignored; `reset` warns that the next F5 replaces an unreadable save. No migration: design 11's 2026-06-10 decision (test-only saves, no importer) covers it until real player saves exist. Lone/mismatched halves still load, filed as `save-pair-consistency`; bug closed
- [x] Track F3 (follow-up) — `misc-low-severity` bundle — perf HUD rings are head-indexed (no per-frame `remove_at(0)`) and stale labels/status keys are erased, not just hidden; `Tool.activities` is read-only so the player's remembered activity index can't go out of range; items 2 (FillVoxel 0.5 nudge) and 3 (raymarch first segment) closed as not bugs with the raymarch header reworded; item 7 repointed at `EditStore::lattice_turns_in`; items 6 (input if-chains) and 7 stay open
- [x] Track H1 (follow-up) — DC mesher arg traps (`dc-mesher-latent-arg-traps`) — a splice is its own binding, `mesh_clipmap_splice`, with both boxes required and refused (error, empty result, retained build untouched) unless each has extent on every axis; `mesh_clipmap` has no box params, so box presence is the entry point, not a value. `grow_world(reuse_frontier=true, refine_budget=-1)` drains the whole retained frontier instead of silently doing nothing, and every rebuild grow resets the heap bound (an unbudgeted one used to report, and leave poppable, the last budgeted grow's stale bound). No existing caller's mesh changes; the one observable difference is `get_last_refine_queue_size()` after an unbudgeted rebuild (stale → 0), which the live preview never issues (its moves pass `refine_us` or 0). Filed evidence on `dc-incremental-emit-ring-insufficient`: a one-shot drain drops 89 triangles (pending gate, ratcheted at ≤ 100); bug closed. Trap 1's old/new red-green was done with `scripts/dev/probe_dc_arg_traps.gd` (the box API was renamed, so the GUT tests pin the new contract, not the old wrong output). Follow-ups filed: `dc-mesher-box-value-sentinels` (same sentinel in `mesh_world`/`grow_world`), `dc-edit-world-stale-refine-frontier`
- [x] Morning brief + play-test list at the bottom of this doc

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

*Drafted by Claude at the end of the session. Everything is merged to local `master`; nothing is
pushed (see "Environment").*

### Needs you first

1. **Single-voxel edits** — the characterization is done. Answer its questions and the fix can be
   designed: [`single-voxel-edits-unexpected`](bugs/single-voxel-edits-unexpected.md).
   In short: Fill makes a ~2.5 m³ smooth mound, 83 % of it outside the target, and the target ends
   about half full. 0 of 982 edits read as a cube. Empty refuses "already air" on 48 % of first
   clicks and can't dig down (a second click refuses 36 of 39 times). Did you expect a crisp 1 m
   cube? Which cell should Fill fill? Should paint cover the whole visible change?
2. **Should terraforming count as cell edits?** Raise, Lower and Flatten emit no
   `voxel_added`/`voxel_removed`, so PartIndex never releases a part they carve, and support and
   detachment never react to them. This predates tonight. The fix is ready (writes now return
   measured flips); the intent isn't:
   [`actions-reshape-no-voxel-events`](bugs/actions-reshape-no-voxel-events.md).
3. **Dig under your own feet:** guard it the way Lower is guarded, or keep Dig as "dig anywhere"?
   The guard would refuse digs aimed within ~4.5 m of your feet:
   [`dig-action-no-validate-no-safety`](bugs/dig-action-no-validate-no-safety.md).

### Decided without you — overrule freely

- **Fixed-bug convention:** I followed `00_INDEX.md`'s preamble. A fixed bug's file is deleted, and
  `closed/` is only for not-a-bug and obsolete verdicts. Track A had archived three fixed bugs; the
  merge deleted them and repointed their links at the fixing commits. The preview before/after
  table is kept below.
- **Scope grew past the plan.** Once A and B landed early, I ran follow-ups: every per-frame and
  per-click GDScript lattice loop moved to C++ (A4, C1, C2, G1, G2), plus backlog bugs with clear
  fixes (D1, E1, F1–F3, H1, I). Each got the same author → two reviewers → fixer loop.
- **Asked-then-answered overnight:** agents asked whether to port the construction attach scan, the
  per-click material paint and the thaw's measurement to C++. The manifesto answers that, so I did
  (C1, G1, G2). Flatten's work generation and the safety scan went too (A1b), because the plan's
  gate couldn't be met otherwise.
- **Event bus re-entrancy (F1):** nested emits dispatch synchronously in full. A subscriber added
  mid-dispatch hears only later emits; one removed mid-dispatch hears nothing more.
- **Saves (F2):** an unreadable save (version bump, bad pair) is refused loudly and kept on disk,
  never overwritten. F5 stays blocked until `reset`.
- **Mesher (H1):** a splice now has its own entry point, `mesh_clipmap_splice`, with required boxes,
  and a box without extent is refused. `grow_world(reuse, -1)` drains the whole frontier. No
  live-caller behaviour changed. I did not apply the same design to `mesh_world`/`grow_world`,
  because that would change the live preview's signatures; it's filed as `dc-mesher-box-value-sentinels`.
- **Behaviour changes to know about:** a sub-cell part (e.g. a 0.5 m log between cell-centre planes)
  now gets no PartIndex record (B3). An MPM thaw seeds particles only from cells it actually
  emptied, and can drop debris a few metres outside the aim when the box rewrite flips extra cells (B4).

### Open questions (evidence in each file)

| Question | Where |
|---|---|
| Re-stamping the same CSG shape in a new material: repaint, or refuse as a no-op (today)? | `csg-restamp-material-only-refused` |
| Sub-cell part identity in PartIndex | `part-index-sub-cell-parts-untracked` |
| A thaw plan the corner carve can't realize: refuse, reshape, or solve exactly? | `mpm-thaw-carve-leaves-planned-cells` |
| StoreWrite's box re-encode flips cells nobody edited (17 air, 1 solid over 190 thaws): repair like `one_cell`? | `mpm-thaw-carve-leaves-planned-cells` |
| Disk-full policy for the DC arena: migrate to RAM, or stop refining? macOS matters? | `mmap-arena-disk-full-sigbus` |
| Save pairs: refuse or warn on a lone or mismatched half; per-version readers once real saves exist; move unreadable saves aside? | `save-pair-consistency` |
| `stamp_sphere`/`stamp_box` UNION repaints terrain it didn't make: test-only, or match `materials()`? | `edit-store-stamp-union-repaints-terrain` |
| Dry run reads the generator twice (~0.045 ms of a refused preview): couple it to the builders, or leave it? | `actions-lattice-dry-run-double-generator` |
| SVD ill-conditioning: interim fix now, or wait for the McAdams rewrite? Does the sim ever get there? | `mpm-svd-ill-conditioned-u` |
| `edit_world` and a stale refine frontier: clear it, or refuse reuse after an edit? | `dc-edit-world-stale-refine-frontier` |
| One-shot frontier drain drops 89 triangles in `emit_incremental` (pending gate test added). Does that match `dcdrop` in play, and change the priority? | `dc-incremental-emit-ring-insufficient` |
| Should `TerrainSdfChanged` carry its source, so DetachmentScout can ignore MPM edits explicitly? | (B4 commit `7e6c225`) |
| Close misc item 6 (player.gd input if-chains) as won't-fix? | `misc-low-severity` |
| 04-event-bus.md "Lifetime & cleanup" predates WeakRef subscriptions: update, or keep as history? | `docs/roadmap/design/04-event-bus.md` |

### Numbers

Preview per call, radius 3, real terrain (A1b; "Before" is pre-`f11d284`):

| Action | Before | After `f11d284` | Now |
|---|---|---|---|
| dig / fill | 0.07 ms | 0.76 ms | 0.055 ms |
| raise | 0.11 ms | 0.65 ms | 0.047 ms |
| flatten | 0.23 ms | 0.73 ms | 0.045 ms |
| CSG sphere | 0.63 ms | 2.5 ms | 0.156 ms |
| beam 6×2×2, resting / +3 m (C1) | — | 0.33 / 0.89 ms | 0.14 / 0.15 ms |

Per click, `execute()`: beam placement 6.3 → 0.70 ms, CSG ~6.5 → 0.70 ms, fill r2 1.33 → 0.16 ms
(G1, G2). 729-cell MPM thaw 9.4 → 6.0 ms (D1, G2). Buried refused CSG preview 0.68 → 0.34 ms (A4).

GUT: 192 tests / 190 passing / 2 pending at the start → **288 / 284 / 4** at the end, 0 failing
throughout. New pending tests are gates for filed bugs (`mpm-svd-ill-conditioned-u`,
`dc-incremental-emit-ring-insufficient`).

### Not done, and why

- **Dig's player-safety guard:** waits on question 3.
- **The DC mesher bugs** (`dc-inside-coverage-cracks` and the rest): design work that's yours;
  tonight only added evidence and a gate test.
- **Nothing was checked on a GPU.** Everything here is headless. The render-visible changes (paint
  at seams, previews, placement) need your eyes; see the play-test list.

### Environment

- **Nothing pushed.** Every `git push` failed: `Permission denied (publickey)` from this session's
  ssh-agent. Branches and `master` are local only; push when you're up.
- **`claude` on PATH reverted to 2.1.274.** `~/.local/bin/claude` was repointed at 22:28, most likely
  by the stable-channel auto-updater, so "Session facts" above is wrong about the pin. A plain
  `claude` relaunch can't run Opus 5.5 until you `claude install 2.1.283` (or later) again.
- The main checkout is back on `master`; the two worktrees under `.claude/worktrees/` are removed.

### Play-test list

1. Aim dig, fill, raise, flatten and CSG sphere around: the ghost should keep up with no hitch.
2. Place beams (rotate, float, rest on an edge): no hitch on click, and attach/refuse where it was.
3. Fill and CSG a new material against earlier edits: no stray repaint on the leaves beside the
   stamp (E1).
4. EmptyVoxel the cell under your feet: refused. Fill near yourself: refused only when the field
   actually buries you (B2).
5. CSG ADD the same shape twice in open air: the second is refused as a no-op (A2).
6. Place a part, dig or CSG it away, then check `parts`: its record goes (B3). With Lower or Flatten
   it probably stays (question 2).
7. `mpmthaw` a block and a sphere: debris comes from what was emptied; watch for strays outside the aim (B4).
8. F5, then quit and reload; then try a save from an older build: a loud refusal toast, and the
   file is untouched (F2).
9. Try FillVoxel and EmptyVoxel with question 1's numbers in mind.
