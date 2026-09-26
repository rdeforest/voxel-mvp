# Overnight 2026-09-26: open questions

*Drafted by Claude from the "Open questions" table in the
[morning brief](overnight-2026-09-26.md#open-questions-evidence-in-each-file), one section per
question. Each one has the context, the options, my take, and a **Robert:** line to answer under.
The bug files have the full evidence. Once you've answered, I'll fold the answers into the bug
files and close or re-scope each one.*

Ordered roughly by how much the answer unblocks.

---

## 1. Should `TerrainSdfChanged` carry its source?

**Where:** B4's commit `7e6c225`; relates to your brief answer on terraforming and fence sag.

**Context.** DetachmentScout ignores edits made "while MPM is active", which is a guess about who made
the edit. B4 showed the guess is fragile: it depends on event order, and it fails silently when a thaw
empties nothing. Several other threads want the same thing: your "voxel modified" event idea (parts
reacting when the ground under them moves), the recorder (which edits to record versus re-simulate),
and the instrument layer (test writes flagged as such).

**Options.**
- Add a `source` field to the edit events (player, instrument, MPM, scout, replay, ...). That touches
  the event classes and every place that emits one.
- Keep inferring the source from state.

**My take:** add it. It's the same change your fence-sag example needs, and it turns a fragile
inference into a fact. I'd do it together with a single "matter changed" event that carries both
the measured cell flips and the source, so raise, lower and flatten stop being the odd ones out
(see brief question 2).

**Robert:**

100% agree with your recommendation.

---

## 2. A thaw plan the corner carve can't carve

**Where:** [`mpm-thaw-carve-leaves-planned-cells`](bugs/mpm-thaw-carve-leaves-planned-cells.md)

**Context.** Thawing a sphere of buried terrain leaves part of it in the ground: radius 5 plans 176
cells and empties 143, and a single buried cell empties none. The carve can only clear lattice
corners that no kept-solid cell shares, so the plan's outer shell stays solid.

**Options.**
- **Solve exactly:** choose corner values so every planned cell goes to air and every kept cell stays
  solid, by a margin. That's the linear program `StoreWrite.one_cell` already solves for a single cell.
- **Refuse** a plan that can't be carved at 1 m.
- **Reshape** the plan into one that can.

**My take:** solve exactly, and refuse (loudly) only where no solution exists. That's the
no-half-measures answer, and the solver already exists for one cell. It also answers question 3, since
one solve can do both.

**Robert:**

Agreed, for the same reason.

---

## 3. StoreWrite's box rewrite flips cells nobody edited

**Where:** [`mpm-thaw-carve-leaves-planned-cells`](bugs/mpm-thaw-carve-leaves-planned-cells.md),
"Separate effect".

**Context.** `StoreWrite.cells` rewrites its whole box, which flips some cells nobody asked to change:
17 to air and 1 to solid over 190 small thaws. That breaks conservation. An emptied cell becomes
particles, sometimes metres from the thaw; a filled cell is matter from nowhere.

**Options.** Repair it, as `one_cell` already does for single cells (constrain unplanned cells to keep
their side), or accept and report it.

**My take:** repair it, inside the same solve as question 2. Unplanned cells become "must stay on the
side they're on" constraints.

**Robert:**

Agreed, per #2 above.

---

## 4. Disk-full policy for the DC cell arena

**Where:** [`mmap-arena-disk-full-sigbus`](bugs/mmap-arena-disk-full-sigbus.md)

**Context.** When the disk under the arena's temp file fills, the next write to a fresh page kills the
process with SIGBUS. Your `./tmp` is on btrfs, whose copy-on-write means a full disk can fault even on
pages written before. Reserving space ahead of time makes the failure visible to code, but growth then
needs a failure path.

**Options.**
- **Migrate to RAM:** move the arena to anonymous memory in place and keep refining, with the existing
  warning pop-up and a risk of running out of memory.
- **Stop refining:** treat the reserved space as the arena's capacity; terrain stays at the detail it
  has, and every allocation needs a graceful stop.

Either option also needs the reservation work, plus NOCOW on btrfs.

**My take:** stop refining, with a loud warning. A full disk is a hardware limit, which the manifesto
accepts as a trade-off, and running out of RAM is a worse way to fail than stopping at the current
detail.

**Also:** does the Mac build matter here? macOS has no `posix_fallocate`, so this would be Linux-first.

**Robert:**

First just thoughts:

* Normally I bias for no-compromise, but I think compromise that standardizes
  on common platform features is acceptable. Therefore, the Mac build (and
  eventually Windows too) matters.

* In the interest of failing early, let's choose conservative memory and disk
  budgets for testing and development. Trying things out with all my ram and
  disk available is fun but not necessarily productive. I'm thinking 32g disk,
  32g RAM and of course 32g VRAM because that's about what my 5090 has when
  it's not running an LLM.

Now for the answer: I don't remember what arena refers to in this context. I
need a refresher. It may also be possible to simplify this answer by not doing
things just because I think they're cool, like using mmap for anything.

---

## 5. Save pairs: lone or mismatched halves

**Where:** [`save-pair-consistency`](bugs/save-pair-consistency.md)

**Context.** A save is two files, the snapshot and the terrain blob. Nothing checks that they belong
together. A lone half loads with a cheerful "Loaded save.", and a failed blob write can leave a new
snapshot beside an old blob.

**You already said** (brief, on the save format): *"We don't need to maintain support for more than
one format until we have play testers. If there's code we can remove now, let's do it."*

**My take, from that:**
- Drop the pre-S4 snapshot-only compatibility.
- Write a shared save id into both files, and write the pair atomically (temp names, then rename).
- Refuse and keep a lone or mismatched half.
- Also remove the v1 blob reader that J1 added, since that's a second format.

The only real question left is **"move an unreadable save aside so F5 works again"** versus **"block
F5 until `reset`"** (today's behaviour). Named saves from doc 22 make blocking less painful.

**Robert:**

Your take sounds right to me. Make it so.

---

## 6. `stamp_sphere` / `stamp_box` repaint terrain the brush didn't make

**Where:** [`edit-store-stamp-union-repaints-terrain`](bugs/edit-store-stamp-union-repaints-terrain.md)

**Context.** These C++ stamps paint every leaf that ends up solid, including existing terrain the brush
never reached. The action write path paints only where the edit made something solid. Only tests and dev
harnesses call these stamps.

**Options.** Treat them as test tools where the rule doesn't matter, or make them follow the same rule
as `materials()` (one condition in `_stamp_region`, plus a test).

**My take:** make them match. The instrument layer in doc 22 will stamp by numbers through these paths,
and a test instrument that paints differently from the game is the kind of trap the split is meant to
remove.

**Robert:**

Yes, make them match. Good call.

---

## 7. Sub-cell part identity in PartIndex

**Where:** [`part-index-sub-cell-parts-untracked`](bugs/part-index-sub-cell-parts-untracked.md)

**Context.** A part thinner than a cell (a 0.5 m log between cell centres) makes no cell solid, so
PartIndex has nothing to key it by and keeps no record.

**Options (from the bug):** release by re-testing the field on change, or a finer identity lattice
once cells go below 1 m.

**My take:** neither. Doc 22 suggests keying parts by their **assembly path**
(`north_wall/merlon[3]`), not by cells, which gives every part an identity whatever its size. I'd park
this until assemblies exist and solve it there.

**Robert:**

100% agree with your take AGAIN. :)

---

## 8. Re-stamping a CSG shape in a new material

**Where:** [`csg-restamp-material-only-refused`](bugs/csg-restamp-material-only-refused.md)

**You already said** (in the bug file): this only arises in testing. In the game it'd be "stack wood
here", and replacing wood with stone means moving the wood out first.

**My take:** close it as moot under directives. The instrument layer's "set a cell's material" command
covers the testing need.

**Robert (confirm):**

Agreed, close it.

---

## 9. SVD ill-conditioning: fix now or wait for the rewrite?

**Where:** [`mpm-svd-ill-conditioned-u`](bugs/mpm-svd-ill-conditioned-u.md)

**Context.** MPM's 3×3 SVD degrades as a deformation nears singular: U stops being a rotation at
σ₂/σ₀ ≈ 1e-8, and at rank ≤ 1 it reads memory that was never written (undefined behaviour). Whether the
simulation ever gets there is unmeasured. The planned McAdams rewrite fixes it properly.

**Options.** An interim fix now (cross-product U's last column when ill-conditioned, and zero `Mat3` on
construction), or wait for McAdams.

**My take:** split it.
- Fix the uninitialized read now, since undefined behaviour is a defect regardless.
- Add a cheap measurement: log the smallest σ₂/σ₀ the sim reaches during thaws. That tells us whether
  the rest is urgent.
- Leave the rest to McAdams unless the measurement says otherwise.

**Robert:**

Agreed.

---

## 10. `edit_world` and a stale refine frontier

**Where:** [`dc-edit-world-stale-refine-frontier`](bugs/dc-edit-world-stale-refine-frontier.md)

**Context.** After an edit, the mesher's saved list of cells waiting to refine can name cells the edit
freed. A later "reuse the frontier" grow would refine stale entries. Nothing does that today; only
`dc_world_preview.gd`'s bookkeeping prevents it.

**Options.** `edit_world` clears the frontier (the next grow re-collects), or refuse reuse after an edit.

**My take:** clear it. That's defined behaviour at trivial cost, with a GUT test for grow → edit →
reuse-grow. This is your mesher area, though, so it's your call.

**Robert:**

Why does the edit not clear the impacted portion of the frontier already? I
would expect an edit to result in an invalidation of stored facts around the
area of the edit, including what needs to be refined. Can we clear just that
which has been made obsolete? Clearing the whole frontier seems .. dramatic.

---

## 11. One-shot frontier drain drops 89 triangles

**Where:** [`dc-incremental-emit-ring-insufficient`](bugs/dc-incremental-emit-ring-insufficient.md)

**Context.** H1 reproduced the incremental-emit drop headlessly. Draining the whole frontier in one
grow drops 89 triangles (596 rendered against 684 from a full re-emit). A pending GUT test is ready as
the gate.

**Questions:** does this match what `dcdrop` shows you in play? And does having a headless repro change
this bug's priority? It's your active mesher thread.

**Robert:**

I have no recollection of what I was seeing in game play. I'd like to
de-prioritize this in hopes of it becoming moot after we make bigger
improvements.

---

## 12. A no-op-looking write still reports `changed`

**Where:** [`edit-store-noop-write-reports-changed`](bugs/edit-store-noop-write-reports-changed.md)

**Context.** Writing the store's own values back over a coarse or inherited leaf moves its samples by
about 1e-8, and the write truthfully reports `changed = true`. Consequence today: at most one extra
re-mesh the first time a thaw lands on such a leaf.

**Options.**
- Keep a leaf's field when all 8 new corners match what it holds. Then every prediction and the test
  oracle must read the kept leaf.
- Accept it, and document `changed` as "some sample moved", which is exact.

**My take:** accept and document. The first option complicates every prediction path for a
1e-8 effect.

**Robert:**

Agreed, I suspect this is another item that will be mooted by bigger work.

---

## 13. Dry run reads the generator twice

**Where:** [`actions-lattice-dry-run-double-generator`](bugs/actions-lattice-dry-run-double-generator.md)

**Context.** A refused CSG preview reads the terrain generator at the same 2,744 points twice, about
0.045 ms of 0.34 ms.

**Options.** Couple the lattice builders to the dry run, cache the generator per column (breaks with the
volumetric generator), or leave it.

**My take:** leave it and revisit when the volumetric generator lands, since the cost profile changes
then.

**Robert:**

Agreed.

---

## 14. Close misc item 6 (player.gd input if-chains)?

**Where:** [`misc-low-severity`](bugs/misc-low-severity.md), item 6.

**Context.** The input handling in `player.gd` uses if-chains, against the house rule. A reviewer
judged them forced by live input state and not worth rewriting.

**My take:** close as won't-fix. Directives will replace this input layer, so rewriting it now is
wasted work.

**Robert:**

Good catch, but I also agree with your take.

---

## 15. Event bus spec: update, or keep as history?

**Where:** [`docs/roadmap/design/04-event-bus.md`](roadmap/design/04-event-bus.md), "Lifetime & cleanup".

**Context.** The section describes `Callable.is_valid()` cleanup, but the bus has used WeakRef
subscriptions for a while.

**My take:** update it. A spec that's wrong about shipped code is stale on arrival, and git keeps the
history.

**Robert:**

Agreed.

---

## Parked for chat (not questions to answer here)

- Player safety and Lipschitz continuity (brief question 3).
- What could go wrong with the event bus's re-entrancy rules (brief, F1).
- Integrating a local LLM for operations like "act on the voxels touching this triangle" (bug file,
  question 8).
- Moving bug tracking to GitHub issues, with closed bugs migrated.
- A glossary doc (MPM, splice, etc.).
