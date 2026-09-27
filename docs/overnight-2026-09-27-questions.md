# Overnight 2026-09-27: questions

*Drafted by Claude from the questions the agents raised, one section per question. Each has the
context, my take, and a **Robert:** line. Questions that later chunks answered are left out; the
morning brief in [`overnight-2026-09-27.md`](overnight-2026-09-27.md) lists what was decided
without you. Evidence is in the named bug files and commits.*

## Needs you first

### 1. Post our findings on Godot's float-parsing issue?

**Context.** Godot's text→double reader is off by an ulp on about 24 % of 17-digit doubles, and it
reads every value below about 1e-308 as 0. Open issue
[#123700](https://github.com/godotengine/godot/issues/123700) covers the rounding but not the
underflow case. We work around both (`bugs/godot-float-parse-inexact.md`,
`roadmap/reference/10-godot-float-parsing.md`). Posting is outward-facing, so I haven't.

**Draft comment:**

> Two data points in case they're useful. (1) Underflow: when the net exponent (written exponent
> minus fractional digits) reaches -309 or below, `dblExp` in `built_in_strtod` overflows to +inf
> and the result is 0, so `2.2250738585072014e-308`, every subnormal, and 17-digit values below
> ~1e-292 parse as 0. (2) Measured against glibc `strtod` on 4.6-stable: 48 % of `%.17g` random
> doubles across 1e-280..1e300 are off, 15.6 % across ±1e6. Happy to share the harness. +1 for
> fast_float.

**My take:** post it, from your account.

**Robert:**

### 2. A grid-aligned 1 m post renders and collides, but the structural code can't see it

**Where:** `bugs/scout-ignores-freeze-flips.md` (F3).

**Context.** F3 made freezes report their measured flips, but letting the detachment scout seed from
them loops on one shape: a 1 m CSG post aligned to the cell grid. Its cell centres sit exactly at
SDF 0, and "solid" means below 0, so the flood (and TerrainSupport) treat the post as air while the
mesher draws it and the collider stands on it. So the scout still ignores freezes.

**Options.**
1. Make the structural solidity test agree with what renders and collides for sub-resolution
   geometry.
2. A loop breaker in the scout (don't thaw a detached component made only of cells the freeze just
   made solid).
3. Keep ignoring freezes.

**My take:** this is really a question about the cell-centre solidity rule, the same rule behind
your single-voxel surprise (a cell with all corners at 0 reads as air). The structural view
disagreeing with what the player sees is the kind of hidden inconsistency the manifesto rules out,
so (1) is the real fix. It deserves a short design discussion first, because every "is this cell
solid" caller depends on it. Until then, (3).

**Robert:**

### 3. Should every box writer keep unplanned cells on their side?

**Where:** `bugs/store-write-reencode-flips-unplanned-cells.md` (F1).

**Context.** Your Q3 answer ("repair it in the same solve") is now applied to the MPM thaw, which
carves exactly with zero stray flips. The other box writers (raise/lower, flatten, fill, dig, CSG,
imprint, instruments, freeze) still re-encode their whole box and can flip a cell nobody edited.

**My take:** apply it to all of them. A stray flip is matter appearing or vanishing, and the solver
runs in well under a millisecond for realistic writes. It's one solver used everywhere, not a
special case.

**Robert:**

### 4. Look at these on a GPU

Nothing tonight was checked visually. The play-test list is at the end of the morning brief. The
ones that matter most:
- **Carved walls** after `mpmthaw 3` and `mpmthaw 5` into a hillside (F1): the solve lowers kept
  cells' far corners to make up for the corners it clears.
- **Stamp paint** next to other materials (E2).

**Robert:**

## Engine and meshing

### 5. Zeroing `Mat3` constructor as insurance?

**Context.** E1 fixed the uninitialized read properly (MemorySanitizer-clean, pinned by tests). A
zeroing constructor would add insurance for future `Mat3` users and costs about 1.5 % of MPM step
time.

**My take:** no. The defect is fixed at its cause, and the tests would catch a regression.

**Robert:**

### 6. Detached floating blocks slide about 130 m and never freeze

**Context.** E1's probe saw thawed blocks land and then slide steadily down the slope near the
origin: about 130 m of drop over 3000 ticks with contact friction 0.35, and they never settle.

**Diagnosed after the brief** (`bugs/mpm-contact-friction-and-damping.md`). The slide itself is
expected: the origin is a 66° cone peak, far past the friction angle of 19.3°. But the contact model
has four real defects: friction is viscous rather than Coulomb (blocks creep on any slope), damping
acts in free flight, the non-unit SDF is used as a distance (2.46× contact overshoot), and the settle
rule freezes slow sliders mid-slide.

**My take:** fix all four as one physics chunk with the tilted-gravity regression test, then look at
thaws and debris on a GPU, since it changes how MPM feels. Okay to schedule?

**Robert:**

### 7. Cell budget: 16 GiB for cells, and per-process accounting?

**Where:** `DC_CELL_RAM_BUDGET` in `engine/voxel_dc/dc_octree.h` (E4).

**Context.** Cells get 16 GiB of your 32 GB budget (about 68 M cells). The limit is per octree, so
the preview, the collision mesher and a splice tree could each reach it.

**My take:** 16 GiB is fine, and yes to a single process-wide counter, since the budget is per
process.

**Robert:**

### 8. Drains got about 12 % slower per cell after the RAM arena

**Context.** E4 made builds about 30 % faster and moves the same or faster, but at radius 256 a
series of drains costs about 12 % more per cell refined. It isn't explained yet.

**Diagnosed after the brief:** not a regression. At an equal number of refined cells the cost is
unchanged (1.84 vs 1.86 µs per cell); the "12 %" compared runs that refined different numbers of
cells. **But it found a real problem:** a "20 ms" drain takes 32–76 ms of wall time, because
collapse and emit after the budgeted refine have no budget (`bugs/dc-drain-collapse-emit-unbudgeted.md`).

**My take:** that belongs in the "compelling, not accurate" session, since it's the mesher's frame
cost.

**Robert:**

### 9. Mesher reads from the main thread while a job runs

**Context.** F4 fenced the debug server's and the status line's reads. Others remain: `dcthreads`
reading timings, `dcverify` and `dcdrop` toggling mesher flags, and the worker writing
`_job_work_ms` while the main thread reads it.

**My take:** put them all behind `is_job_running()`, or defer them to the next idle frame the way
`set_max_cells` does.

**Robert:**

### 10. Meshing questions for the "compelling, not accurate" session

Park these for that session, since they're your area and interact with reference note 09:
- Should `edit_world` refine its edited band through the budgeted frontier instead of all at once
  inside the edit call (E3)?
- Doc 20 §E: pursue "reconcile_edit re-checks prune decisions outside the edited box" (E3)?
- Should a budgeted graft put coarse cells in first, rather than leave an absent strip (E4)?

**Robert:**

## Events and structure

### 11. Chunked freezes announce their flips over several frames

**Where:** `bugs/mpm-chunked-freeze-flips-arrive-late.md` (F3).

**Context.** Large freezes (over 24 m) re-mesh in chunks over several frames, and each chunk's event
carries the flips inside it, so a listener can see a later event before a freeze's flips have all
arrived. The options are: announce all flips at the write, flush pending chunks before any later
announcement, or drop the chunking.

**My take:** flush pending chunks before later announcements. It keeps the frame-time win of
chunking and restores ordering.

**Robert:**

### 12. The scout's MPM gate: `active_count() == 0` or `is_idle()`?

**My take:** `is_idle()`. It's the stronger check, and it's what `is_quiescent()` already uses.

**Robert:**

### 13. A console `mpmthaw` now counts as an instrument edit

**Context.** So the scout detaches whatever a manual thaw undercuts once the debris settles.

**My take:** that's right. Instrument edits are real edits with true consequences.

**Robert:**

### 14. Fence on a hill: it falls rather than sags

**Context.** A part left hanging by terraforming now detaches and falls through MPM. A partial sag
needs parts to have their own physics response, which doesn't exist yet.

**My take:** accept falling for now; sagging arrives with parts in the continuum sim.

**Robert:**

### 15. Lambda or `.bind()`ed subscriptions on the event bus

**Where:** `bugs/event-bus-lambda-and-bound-callables.md`.

**My take:** refuse them loudly at subscribe time. Today they fail silently at first delivery.

**Robert:**

### 16. Should events carry a world or store id?

**Context.** The bus is global, so the replay runner allows one live scenario at a time. Comparing
two replays side by side, or running more than one world, would need events to say which world they
belong to.

**My take:** defer it until something needs two worlds.

**Robert:**

## Saves

### 17. F5 refuses more often now ("world still settling")

**Context.** Quiescence now includes the scout's pending work (G4.0), which is busy for a few frames
after most edits.

**My take:** make F5 wait and then save once the world is quiescent, rather than refuse.

**Robert:**

### 18. Two save-behaviour confirmations

- An interrupted save whose temporaries both read back whole is finished on the next load, so the
  newer save wins. **My take:** keep it.
- A failed rename after commit shows the failure toast, although the save is committed and completes
  later. **My take:** give it a warning style instead.

**Robert:**

### 19. Check loaded inherited leaves against their source?

**Where:** `bugs/edit-store-blob-inherited-corners-unchecked.md` (F2).

**My take:** yes. It's cheap, and it matches J1's "vet the whole blob before touching the store".

**Robert:**

## Scenarios and recording

### 20. Recorder refinements

Answer in one line, e.g. "yes to all":
- A `settle` step records how many frames it took, so a replay flags a timing divergence right
  there. **Yes, I think.**
- `rec stop` stores a fingerprint of the live world, so a replay proves it reproduced it and a
  missed recorder hook is caught. **Yes.**
- `rec fresh` refuses on an edited world instead of resetting it, unless forced. **Yes.** It avoids
  losing work.
- Console `mpmthaw` aims with the SDF raymarch like player clicks, instead of the physics raycast.
  **Yes.** That's consistent, and testable headless.
- The recorder test's thaw isn't timing-sensitive, so it should thaw something that visibly falls.
  **Yes.**
- Rename the marks' `cells` key to `cell_slots`. **Yes;** nothing depends on it yet.

**Robert:**

## Instruments and the probe

### 21. Retire FillVoxel and EmptyVoxel?

**Context.** The instrument layer now does exact writes, so these are neither good instruments nor
game verbs.

**My take:** remove them from the tool belt.

**Robert:**

### 22. The probe overlay

**Context.** Doc 22 mentions an optional in-world overlay: the owning leaf's boundaries (and its
source leaf's) plus corner dots coloured by sign. `leaf_info` now supplies every number it needs.

**My take:** yes, styled to the watercolor look. It's your call on how it looks.

**Robert:**

### 23. Instrument rescue: fly with noclip when buried

**My take:** keep noclip when buried, since plain fly would leave you stuck in the stone.

**Robert:**

### 24. Your single-voxel expectation

**Context.** You expected a single-cell edit to leave the cell's corners at SDF 0. Gameplay counts a
cell as solid only when its centre is below 0, so a cell with all corners at 0 reads as air. Did you
mean "the surface passes through the corners" or "the cell ends up solid"? This connects to
question 2.

**Robert:**

## Test housekeeping (from F5)

### 25. Three small ones

- **Console history:** every GUT run loads and rewrites `user://limbo_console_history.log` through
  the LimboConsole autoload, so playing while tests run can lose your console history. Stop tests
  from persisting it? **My take:** yes, with a pre-run hook rather than a patch to the vendored
  addon.
- **Leftover directory:** an empty, unreferenced `user://dc_arena_refused/` (from the removed mmap
  arena's test) is in your user data. Delete it? **My take:** yes.
- **Long test files:** `test_instruments.gd` and `test_saved_world.gd` are over the 350-line budget
  (both got shorter tonight). **My take:** leave them under the relaxed GDScript rule.

**Robert:**
