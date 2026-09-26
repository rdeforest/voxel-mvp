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

## 7. Player-safety "was it already solid/air" is judged only at sampled points
*Added by Claude (agent), 2026-09-25; location updated 2026-09-26 after the C++ port.*
`EditStore::lattice_turns_in` (`engine/voxel_dc/edit_store_predict.cpp`), reached through
`SdfLattice.solidifies_in` / `empties_in`, finds exactly where the write makes new solid or air. But
it only checks what was there *before* at the overlap corners and the cell sample points. If the
store is already solid at every tested point and the write adds solid between them, the check isn't
proven exhaustive. That errs toward refusing. **Fix (optional):** bound the prior field per leaf the
way the written field is bounded.

## References
`scenes/player/player.gd`, `scripts/actions/sdf_lattice.gd`, `engine/voxel_dc/edit_store_predict.cpp`.
