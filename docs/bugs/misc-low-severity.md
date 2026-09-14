# Misc low-severity findings (code review 2026-06-22)

**Status:** Deferred (2026-06-22). A bundle of small, individually-minor findings from the full-sweep code
review. Grouped to avoid index bloat; split any one out if it grows teeth.

## 1. `voxel_utils.gd` docstring contradicts the code (misleading shared util)
`scripts/voxel_utils.gd:5-7`. The docstring for `for_each_in_bounding_box` says the second param is the far
*corner* ("the other corner; all axes of origin must be ≤ dimensions"), but the code treats it as an
**extent** added to origin (`x_to := ceil(origin.x + dimensions.x)`, `:9-27`). Callers pass it correctly as
a size (`footprint_from_aabb` passes `cell_aabb.size`), so the code is right and the doc is wrong — a reader
trusting the comment would pass an absolute corner and get a doubled box. **Fix the doc.**

## 2. `action_factories.gd` hardcoded 0.5 nudge for fill-voxel
`scenes/player/action_factories.gd:77` nudges `+hit_normal*0.5` while the empty-voxel side and everything
else use the shared `SURFACE_NUDGE` constant. The `0.5` lands exactly on a cell boundary, and `floori` of an
exact integer picks the higher cell — can pick the wrong cell on negative-facing (`-x/-y/-z`) surfaces.
**Fix:** use a consistent nudge derived from the shared constant; verify the target cell on negative faces.

## 3. `terrain_raymarch` leaves the first `[0, step)` segment unsampled
`scripts/terrain_raymarch.gd:17-21`. The march starts at `t = step` (0.2 m), so a thin solid sliver within
0.2 m of the camera is stepped over. The bisection bracket is still valid (origin was confirmed air at
`:15`), and iterations are bounded — so this is correct except for the near-camera gap, which is a minor
inconsistency with the "never stepped over" intent. **Fix (optional):** sample from a small initial `t` or
test `[0, step)` explicitly.

## 4. `perf.gd` ring buffers use O(n) `remove_at(0)`; status dicts never evict
`scripts/ui/perf.gd`. The frame/mark/queue arrays are bounded (`GRAPH_CAP=256`, good) but maintained with
`remove_at(0)` (`:138-142`) — a 256-element memmove every frame, ×3 arrays, even while hidden (recording
runs before the `if not _shown` gate at `:143`). And `_times`/`_status` dicts skip stale entries in display
but never delete them (`:155,168`), so they grow with label cardinality; the header comment (`:90`) claims
stale entries "drop off" — they drop off the *display*, not the dict. All bounded in practice; pure smell.
**Fix (optional):** head-index ring buffer; evict stale dict keys; correct the comment.

## 5. `_select_activity` / `current_activity` index invariant unenforced
`scenes/player/player.gd:161`. `current_activity()` reads `_activity_indices[tool_index]` after an
`is_empty()` early-return, but nothing guards a remembered index that exceeds a tool's (shrunk) activity
count. Can't happen today (indices only set via the bounds-checked `_select_activity`), but there's no
invariant if activity lists ever shrink. Noted, not urgent.

## 6. Input-layer if-chains brush the no-if-chain house rule
`scenes/player/player.gd:187-205` (`_on_key_pressed` special-cases ui_cancel/`?`/Ctrl+E before the dict
lookup) and `:253-258` (`_placement_chord_axis` W/A/E chain). Most are *forced* by live-state dependencies
(focus gating; axes depend on live `cam_basis`, so a dict would need lambdas) and are the boring-correct
choice. Flagged for completeness against the explicit rule; not worth rewriting. (Keycode map scanned: no
duplicate or missing bindings.)

## References
`scripts/voxel_utils.gd`, `scenes/player/action_factories.gd`, `scripts/terrain_raymarch.gd`,
`scripts/ui/perf.gd`, `scenes/player/player.gd`.
