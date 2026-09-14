# DC budget controller: coarsen bias near the cell ceiling, re-tunes only on job completion

**Status:** Deferred (2026-06-22). Diagnosed by code review. Recovers on its own (not a deadlock) —
confirm whether the bias is intended.

## Symptom (expected)
`eps_px` ratchets coarser than necessary when the octree is near its cell budget, and doesn't re-tune while
the player is stationary even if the frame goes over budget.

## Cause
`scripts/dc/dc_world_preview.gd`.

1. **Coarsen ratchet** (`:465-474`): the "lower eps / refine more" branch (`under`) is gated on
   `get_octree_cell_count() < max_cells`. Once cells hit `max_cells`, `under` is permanently false until a
   frame happens to be under *both* the cell budget and the frame budget in the same tick — so `eps_px` can
   only rise (coarsen) in the meantime. It recovers, but it's biased coarse near the ceiling. The
   oscillation guards themselves are fine (hysteresis 0.8–1.0, asymmetric ×1.4/×0.9, 0.01 deadband, no
   division).

2. **Event-driven, not per-frame** (`_control()` called only from `_finish()`, `:427`): the controller
   re-tunes only when a mesh job completes. If the player is stationary with eps at floor and no job is in
   flight, a frame that goes over budget (e.g. another subsystem spikes) won't raise eps until something
   else triggers a job. The "MAX DETAIL until the GPU complains" loop is only closed on job boundaries, not
   continuously.

## Proposed fix
If the coarsen bias is unwanted, allow eps to lower whenever the frame is under budget regardless of the
cell-count gate (or decouple the two budgets). If the stationary-overrun case matters, drive `_control()`
from `_process` on a frame-time signal rather than only from `_finish()`. Both are behavioural tunings —
confirm intent before changing, since "hold detail where it already fit" may be deliberate.

## References
`scripts/dc/dc_world_preview.gd` `_control`/`_finish`.
