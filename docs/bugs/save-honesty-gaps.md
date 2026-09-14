# Save honesty: silent non-quiescent save, and silent save-discard on version bump

**Status:** Deferred (2026-06-22). Diagnosed by code review. Low severity; both are "fails quietly where it
should speak up."

## A. force_quiescent gives up silently after 100k iterations
`scripts/structural_integrity.gd:55-59`. The quiescence drain is guarded by `guard < 100000`; if the dirty
queue genuinely can't drain in 100k iterations, the loop exits and the save proceeds **non-quiescent** with
no log, no Toast — contradicting the "save stays honest / settled" intent the surrounding comment states.
Low risk given the support epsilon, but a save that silently captures a non-settled world is exactly the
thing the gate exists to prevent.
**Fix:** log/Toast when the guard trips (and consider refusing the save rather than writing an unsettled one).

## B. EditStore version check silently discards all saves on a SAVE_VERSION bump
`scripts/dc/edit_store_manager.gd:50`. The blob loader is strict-equality on magic AND version
(`get_32() != SAVE_VERSION → return false`). Unlike `WorldSnapshot` (which defaults missing fields for older
versions), there's no migration path for the EditStore blob — bumping `SAVE_VERSION` silently discards every
existing terrain save with no user-visible warning. Strict equality is the honest choice for a format with no
field-defaulting, but the *silence* isn't.
**Fix:** surface a Toast ("save format changed — terrain reset") on version mismatch, or add a migration
shim. At least don't fail to a blank world without telling the player.

## References
`scripts/structural_integrity.gd` `force_quiescent`; `scripts/dc/edit_store_manager.gd` (blob version check).
