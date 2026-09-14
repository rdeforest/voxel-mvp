# DC mesher: unenforced preconditions in the C++ entry points (latent, no live caller)

**Status:** Deferred (2026-06-22). Diagnosed by code review. **Not reachable by any current caller** —
filed so the traps are documented before someone adds a caller that hits them.

## Traps

1. **`mesh_clipmap` retain heuristic conflates "default" with "intentional box."**
   `engine/voxel_dc/dc_octree_mesher.cpp:104` — `retain = (emit_min == emit_max) && (build_min == build_max)`
   is a *value* test meaning "no box → full build → retain." A caller passing a legitimate degenerate
   non-zero box (e.g. `emit_min == emit_max == (5,5,5)`) is silently treated as a full build and retained,
   and `oct.emit_filter` is left unset (`:148,156` also gate on `min != max`), so the emit box is ignored
   entirely. Equal-but-nonzero is an unhandled third state.

2. **`grow_world(reuse_frontier=true, refine_budget=-1)` is a no-op drain.**
   `engine/voxel_dc/dc_octree_mesher.cpp:351-358` — `reconcile(0)` is skipped when `reuse_frontier`, and
   `refine_selected` only runs when `refine_budget >= 0`. The intersection skips both, so the call
   reaccumulates + recollapses against a stale frontier and reports a stale `_last_refine_queue`. Two
   independent guards with a hole at their overlap. The only `reuse=true` caller
   (`dc_world_preview.gd:262`) always passes a positive refine budget, so it's unreachable today.

## Proposed fix
Cheap insurance: assert the precondition (or document it at the binding). For (1), distinguish "box passed"
from "box equals" with an explicit flag rather than a value test. For (2), either forbid the combination or
make `reuse_frontier` imply a refine pass.

## References
`engine/voxel_dc/dc_octree_mesher.cpp` `mesh_clipmap`/`grow_world`.
