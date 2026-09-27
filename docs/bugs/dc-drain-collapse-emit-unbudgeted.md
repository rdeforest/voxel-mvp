# A "20 ms" refine drain takes 32–76 ms: collapse and emit have no budget

*Filed by Claude (agent), overnight 2026-09-27, found while diagnosing open question 8 (a suspected
12 % drain slowdown after the RAM arena). Harness: `scripts/dev/diag_drain_phases.gd -- <radius>
<budget_us>`.*

**Status:** Open. Severity med: it breaks the 20 ms frame target during drains. The mesher is
Robert's area; this is evidence for the "compelling, not accurate" design session.

## The suspected slowdown was an artefact
At an equal number of refined cells the cost is unchanged by the RAM arena (commit `2ffbf33`):
1.84 µs per cell now (665–669 K cells in 1225–1234 ms) against 1.86 before (667 K in 1.24 s).
Refine itself got faster (0.90 → 0.77 µs per slot), so more cells fit in a 20 ms budget, and those
extra cells carry the collapse/emit cost below. Per-cell cost isn't comparable across runs with
different cell counts.

Radius 256, 30 reuse drains, current binary:

| drain budget   | cells refined | total        | µs per cell | refine µs per slot |
|----------------|---------------|--------------|-------------|--------------------|
| 20 ms (3 runs) | 772–780 K     | 1487–1520 ms | 1.93–1.96   | 0.78               |
| 17 ms (2 runs) | 665–669 K     | 1225–1234 ms | 1.84        | 0.77               |
| 15.5 ms        | 618 K         | 1083 ms      | 1.75        | 0.76               |

## The real problem
`refine_selected` (`engine/voxel_dc/dc_octree.h:1614-1650`) stops on wall-clock time, but the
`recollapse_and_mesh` step after it (`dc_octree.h:1133`, with `emit_incremental` at `:1052`) has no
budget. It is 59 % of the series; its cost per drain grows from 11 ms to 49 ms across the 30 drains,
with 45–56 ms spikes on drains that do a full emit. So a drain budgeted at 20 ms takes 32–76 ms of
wall time.

**Not confirmed:** collapse/emit may be up to ~10 % slower per cell than before the arena change,
possibly from the extra block lookup per `cells[]` access (`engine/voxel_dc/dc_cell_arena.h:55`) in
serial tree walks. Settling that needs an A/B against an old binary.

## Options
- Put collapse and emit under the same frame budget (incremental, resumable), or fold them into the
  refine budget.
- Report refine µs per slot and collapse ms separately in benches, so drains are compared fairly.
