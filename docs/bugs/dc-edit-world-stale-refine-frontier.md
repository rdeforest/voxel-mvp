# `edit_world` leaves the refine frontier naming cells the edit may have freed

*Filed by Claude (agent), overnight 2026-09-26, surfaced while reviewing Track H1 (dc mesher arg traps).
From reading the code; not reproduced.*

**Status:** Open. Severity low (latent: the live preview never issues a reuse grow after an edit). An
unguarded API invariant, enforced only by the GDScript caller's bookkeeping.

## Symptom
`grow_world(reuse_frontier=true)` pops cell indices from the frontier (`Octree::refine_cands`, bound
`refine_heap_end`) that the previous budgeted grow collected, with no validity check
(`Octree::refine_selected`, engine/voxel_dc/dc_octree.h). `edit_world` (dc_octree_mesher.cpp) and
`Octree::reconcile_edit` never touch the frontier or `refine_pending`, but the edit can:

- `make_leaf` a coarsened ancestor, which `kill_subtree`s the queued leaf and pushes its slot on
  `free_list`; a later `build()` may hand the slot to an unrelated cell;
- `grow_subtree` a queued leaf in place, so a later pop re-grows an internal node and orphans its old
  subtree (not returned to `free_list`).

A budgeted `grow_world(reuse=false)` → `edit_world` → `grow_world(reuse=true)` sequence would then refine
stale indices. `mesh_world` is safe (it allocates a fresh `DCOctreePersist`), and a non-reuse grow clears
the frontier.

## Why nothing hits it today
`dc_world_preview.gd`: `incremental_edits` defaults to false (edits go through `mesh_world`). With it on,
`_finish` sets `_refine_pending = _job_is_grow and ...`, so after an edit job the next grow is a move or an
`_eps_dirty` drain, both with reuse=false.

## Proposed fix
`edit_world` clears the frontier the way a rebuild grow does (`refine_cands.clear()`,
`refine_heap_end = 0`, `refine_pending = false`), so a reuse grow after an edit is a defined no-op and the
caller's next move re-collects. Alternatively refuse reuse after an edit. Needs Robert's call; add a GUT
test for the grow → edit → reuse-grow sequence either way.
