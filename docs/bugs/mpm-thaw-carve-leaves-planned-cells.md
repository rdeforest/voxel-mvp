# The MPM thaw carve leaves planned cells that touch kept terrain

*Filed by Claude (agent) on 2026-09-26, from the fix for mpm-thaw-events-unmeasured.*

**Status:** Open, solver built (2026-09-27), not yet wired into the thaw. Severity low: the
detachment auto-trigger thaws a whole piece with air around it, which clears completely; this bites
the manual `mpmthaw` and any partial thaw.

## Symptom
Thaw a sphere of buried terrain and part of it stays in the ground. On the game's field
(`EditStoreManager.setup()`, centre `(0.5, surface - 3, 0.5)`), `thaw_sphere` plans the cells whose
centre is solid and empties fewer:

| radius | planned | emptied |
|--------|---------|---------|
| 3      | 63      | 52      |
| 5      | 176     | 143     |

A single buried cell (`thaw_cells([cell])`) empties nothing.

Until the events fix, every planned cell got 8 particles and a `voxel_removed` whether or not it
went air, so these cells were in the store and in the sim at once (duplicated matter). Now events
and particles follow the measured flips (`MpmStructure.thaw_cells`), so the thaw is honest about
what it moved; it just moves less than it was asked to.

## Cause
`MpmStructure._carve_corners` clears a lattice corner only if no kept-solid cell touches it, so the
wall stays clean. A planned cell next to kept terrain keeps those shared corners, and its centre is
the mean of its 8 corners, so with a few corners raised to `SDF_AIR` it usually still reads solid.
The whole outer shell of a thaw in solid ground is such cells.

## Separate effect seen while measuring
`StoreWrite.cells` rewrites its whole box (work plus a 1-cell margin, squared to a cube) from the
field's own corner samples. The generated field's value at a cell centre is not the trilerp of its
corners, so the rewrite alone flips some cells nobody edited: 17 air and 1 solid over 190 small
terrain thaws. The thaw now reports these (they are real changes to the store); whether the rewrite
should be allowed to make them at all is the same question every StoreWrite caller has
(`StoreWrite.one_cell` repairs it for single cells by LP).

These flips break conservation. An unplanned cell the rewrite empties becomes 8 particles, so
its matter shows up in the sim, possibly metres from the thaw: a radius-1.4 thaw emptied a cell
about 3 m outside the sphere. An unplanned cell the rewrite fills gets a `voxel_added` and matter
from nowhere, because nothing takes it out of the sim.

A thaw whose carve empties no cell leaves MPM idle, and DetachmentScout reads any edit made
while MPM is idle as a player's. `thaw_cells` sends no `TerrainSdfChanged` when its rewrite changed
nothing, so the scout re-floods such a piece at most once rather than every frame. Once the
carve can realize its plan, that case goes away.

## Proposed fix
Solve the carve like `StoreWrite.one_cell` does for one cell: pick corner values so every planned
cell's centre lands past zero toward air and every kept cell's stays solid, by a margin. Where no
such values exist, the plan is not carveable at 1 m and should be refused or reshaped, not silently
shrunk. Needs a decision on which (see the morning brief).

**Decided (Robert, Q2 + Q3 of the 2026-09-26 questions):** solve exactly, refuse loudly only where no
solution exists, and repair the rewrite's stray flips in the same solve.

## Progress, 2026-09-27

*Drafted by Claude (agent).*

`EditStore.predict_carve(cells, max_margin = 4)` (`engine/voxel_dc/edit_store_carve.cpp`, solver in
`carve_solver.cpp`) is the solve. It returns a lattice for `StoreWrite.write`, or a refusal naming the
cells. Gated by `test/test_edit_store_carve.gd`. The first six tests fail when the solve is skipped
(the target written as is, which is the old corner carve); the seventh (the 1x-only face, below)
fails without the solver's margin-scale descent.

**The problem.** The write box is the plan's box plus a margin, squared to a cube. Every cell in it
has a requirement:
- a planned cell must read ≥ `CELL_EDIT_SDF`;
- every other cell must stay on the side it reads now, by `CELL_KEEP_SDF`.

A cell reads the mean of its 8 corners, so each requirement is one sparse row. The corners on the
cube's faces are held as they are, because the leaves beyond keep them and moving one would open a
seam. Interior corners may range over `[SDF_SOLID, SDF_AIR]`, widened to take in their current value.
The solve heads for the least-squares projection of the old corner carve (`SDF_AIR` at each planned
corner that no kept-solid cell touches, the current value everywhere else) and stops at the first
feasible iterate, so the result is a feasible field near that carve, not provably the nearest. Where
the old carve already meets every cell it is returned unchanged, and the hole keeps its clean wall.
(The brief said "prefer minimal change to existing corners"; the target is the old carve instead, so
carved interiors sit at `SDF_AIR` rather than just past `+CELL_EDIT_SDF`, which would put the hole
wall inside the planned cells. A question for Robert.)

**Solver: why not a simplex.** `one_cell`'s dense simplex was sized for 9 unknowns. A 729-cell block
has about 1,700 unknowns and 1,300 rows, and a slab at the thaw's particle cap has about 27,000 and
24,000; a dense tableau would take minutes. The solver here is dual coordinate ascent on the
least-squares projection (Hildreth's method, with the bounds folded into the primal). Each row touches
8 corners, so a sweep costs O(cells) and memory is O(corners). Each cell aims at twice its margin, and
the solve stops once the float32 values meet the true margins, read back the way the store reads them
(bit-identical to `EditStore.sample` after a 1 m write; within float32 rounding where finer leaves
already sit in the box).

**Infeasibility.** When there is no solution, the conflicting cells' multipliers grow along a Farkas
ray. Every 256 sweeps, their growth is checked as a certificate: bound the combined requirement's
largest possible value over the corner bounds, and show it falls short. A refusal therefore carries a
proof and names the cells in it; it is never a timeout passed off as one. If the sweep budget
(20,000) runs out without a proof, the refusal says so (`proven = false`).

Aiming at twice the margin can be impossible when the true margin is not. The dual then diverges
along a ray that proves only the doubled margins impossible, so the solver halves the aim's excess
over 1 and restarts, down to 1 + 1/64. A plan that meets its margins but not 1/64 more than them can
still end at the sweep budget (`proven = false`) although it is solvable. The test holds a face at
4.97 instead of 5, feasible at 1x and not at 1.485x, and must solve at margin 1.

A proof that leans on the held faces may be caused by the box rather than the plan. In that case the
margin grows by one cell and the solve reruns, up to `max_margin`. The test pins a sharp solid face
whose face cell conflicts with its planned neighbour at margin 1 and is solved at margin 2. A refusal
at `max_margin` whose proof still leans on the faces says `pinned = true`: it shows only that no field
exists within that box, not that the plan is uncarveable.

**Measured on the game's field** (`scripts/dev/bench_carve.gd`, one solve, headless):

| plan | cells | emptied | stray flips | box | sweeps | time |
|------|------:|--------:|------------:|----:|-------:|-----:|
| sphere r=3 | 63 | 63 | 0 | 9³ | 16 | 0.1 ms |
| sphere r=5 | 176 | 176 | 0 | 12³ | 16 | 0.2 ms |
| lone buried cell | 1 | 1 | 0 | 4³ | 8 | <0.1 ms |
| block 9³ (674 of them solid) | 729 | 674 | 0 | 12³ | 56 | 0.6 ms |
| slab 27×1×27 (333 solid) | 729 | 333 | 0 | 30³ | 136 | 19 ms |
| checkerboard 7³ (pathological) | 172 | all solid ones | 0 | 10³ | 2,928 | 19 ms |

Across 25,600 near-surface r=1.4 plans within 80 m of the origin (`scripts/dev/find_reencode_flip.gd`),
re-encoding the box alone flips a cell at 1,416 of them, a cell to solid at 488 (none of those within
20 m of the origin). The solve refused none of the 25,600. The tests pin one spot of each direction.

With `SDF_AIR` bounds, a plan the solve provably can't carve seems to need either a held face (which
the margin growth handles) or an alternating pattern hundreds of cells across. I found no realistic
plan that it refuses.

## Follow-up (not done: the wiring is Track G's file tonight)

`MpmStructure.thaw_cells` should build the plan as now, call `predict_carve`, and write the result
with `StoreWrite.write(store, SdfLattice.predicted(d), [])`. On a refusal it should refuse the thaw
loudly with `d.conflict`, per Q2. `_carve_corners` / `_corner_clears` then go, and so do these tests'
reasons to exist:
- `test_thaw_of_an_enclosed_cell_moves_nothing` and
  `test_thaw_that_changes_nothing_announces_no_edit`: their premise was the carve failing, so
  re-baseline them.
- `test_thaw_events_are_the_measured_flips`: its preconditions assert that the stray flip and the
  surviving planned cell happen.

The wiring should call `predict_carve(cells)` without a margin argument, so the default stays the one
C++ definition (`EditStore::CARVE_MAX_MARGIN`, bound as the argument's default), and treat
`proven && pinned` as "not carveable in the box it may rewrite", not "not carveable".

Debt the wiring inherits, not new with this solve: the rewrite is a cube (a lattice has one `dim`), so
a flat plan rewrites far more than its span (a 27×1×27 slab rewrites 30³), and a 1 m write replaces
any finer leaves inside it with the 1 m trilerp. Latent while every writer works at 1 m; filed as
[edit-store-1m-write-flattens-finer-leaves](edit-store-1m-write-flattens-finer-leaves.md).

This bug closes with that wiring.
