# Misc low-severity findings (code review 2026-06-22)

**Status:** Deferred (2026-06-22). A bundle of small, individually-minor findings from the full-sweep code
review. Grouped to avoid index bloat; split any one out if it grows teeth.

Items 1–5 are gone: 1, 4 and 5 were fixed; 2 and 3 were not bugs
([closed/fill-voxel-half-nudge-tie](closed/fill-voxel-half-nudge-tie.md),
[closed/raymarch-first-segment-unsampled](closed/raymarch-first-segment-unsampled.md)). The
numbers are kept so older references still land. *(Note drafted by Claude, 2026-09-26.)*

## 6. Input-layer if-chains brush the no-if-chain house rule
`scenes/player/player.gd:187-205` (`_on_key_pressed` special-cases ui_cancel/`?`/Ctrl+E before the dict
lookup) and `:253-258` (`_placement_chord_axis` W/A/E chain). Most are *forced* by live-state dependencies
(focus gating; axes depend on live `cam_basis`, so a dict would need lambdas) and are the boring-correct
choice. Flagged for completeness against the explicit rule; not worth rewriting. (Keycode map scanned: no
duplicate or missing bindings.)

## 7. (moved)
Split out as [`player-safety-misses-sub-cell-burial`](player-safety-misses-sub-cell-burial.md), because
this item had the direction backwards: the check misses burials; it doesn't over-refuse.

## References
`scenes/player/player.gd`, `scripts/actions/sdf_lattice.gd`, `engine/voxel_dc/edit_store_predict.cpp`.
