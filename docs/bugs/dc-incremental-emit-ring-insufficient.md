# DC incremental emit: neighbour-ring expansion is a heuristic, not provably sufficient

**Status:** Deferred (2026-06-22). Diagnosed by code review. This is the **live edge** of the recent
dropped-triangle fixes (commits `c448d8d`, `3c434ff`, `4bbdd5f`) — flagged so it's not forgotten if drops
recur.

## Symptom
Dropped / dangling triangles at the boundary of an incrementally re-meshed band. Mitigated by the recent
"re-emit dropped cells' neighbours" / "expand re-emit set by one neighbour ring" commits.

## Cause
`engine/voxel_dc/dc_octree.h:982-1032` (`emit_incremental`), expansion at `:998-1004`. When the changed band
is re-emitted, `emit_walk_dirty` collects the render leaves but `try_edge` needs *their* ring-neighbour
cells slotted too. The current fix expands the re-emit set by **one** neighbour ring. But a coarse leaf
adjacent to the changed band can have a ring cell **two shells out** — outside the one-ring expansion — so
the heuristic isn't provably complete. The structural fix (per-triangle owner cell-index + ring tracking
during meshing) is recorded as rejected in [[dc-inside-coverage-cracks]] as more fragile than the proactive
crack-fix; the one-ring expansion is the pragmatic stand-in.

## Reproduced headlessly (2026-09-26)
*Added by Claude (overnight Track H1).* A drain that refines the whole frontier in one grow drops
triangles: `test_dc_world_octree.gd` `test_grow_world_one_shot_drain_incremental_emit_is_complete` (pending
until fixed) builds the real-terrain window at eps 32, grows to eps 2 with a zero refine budget (frontier
of 298), then drains it with `grow_world(..., -1, ..., reuse_frontier=true)`. The drop catcher
(`set_emit_diff(true)`) reports 89 dropped triangles on that one grow (86 when the first grow had 100 µs);
the rendered set is 596 non-degenerate triangles against 684 from a full re-emit (`remesh`) of the same
tree. A finite budget of 1e9 µs gives the same numbers, so this is the incremental emit, not the unbudgeted
drain. Metered 100 µs drains (~118 grows) also drop (~200 cumulative, timing-dependent) but end on the full surface, which is
why `test_grow_world_persistent_frontier_drains_with_reuse` passes. Probe: `scripts/dev/probe_dc_reuse_drain.gd`.

## Proposed fix
If drops recur: either widen the expansion to cover the full ring reach of any coarse leaf touching the band
(bounded by the local max cell size), or adopt the per-edge owner-ring tracking. Add a headless gate that
diffs incremental-emit triangle set against a full re-emit of the same region (the `dcdrop` catcher from
commit `4bbdd5f` is the basis) and asserts zero divergence across a move + several edits.

## References
`engine/voxel_dc/dc_octree.h` `emit_incremental`/`emit_walk_dirty`; commits `c448d8d`/`3c434ff`/`4bbdd5f`;
[[dc-inside-coverage-cracks]].
