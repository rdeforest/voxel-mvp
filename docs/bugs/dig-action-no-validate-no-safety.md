# DigAction: validate() always true, preview disagrees, no player-safety guard

**Status:** Deferred (2026-06-22). Diagnosed by code review. Possibly partly intentional — confirm intent.

## Symptom
- Dig over pure air shows a "refused" (greyed) ghost but still executes the carve.
- Digging the floor out from directly under the player is permitted — no clearance/burial guard, unlike
  every sibling additive action.

## Cause
`scripts/actions/dig_action.gd:25` — `validate()` returns `true` unconditionally, while `preview()` sets
`p.refused = p.is_empty()` (`:44`). The ghost computes refusal; the action ignores it.

Separately, Dig has **no** `PlayerSafeAction` check. Bell, Flatten, and CSG all call `buries()`/`drops()`
before mutating; Dig does not. So the refuse-don't-deform contract is only half-applied here.

## Proposed fix
Make `validate()` mirror the preview: refuse when the carve set is empty. Decide explicitly whether Dig
should also refuse when it would drop the player (probably yes for consistency; if "dig anywhere" is a
deliberate affordance, document that instead). Either way, ghost and action must agree.

## References
`scripts/actions/dig_action.gd`; `scripts/actions/player_safe_action.gd` (the guard the siblings use).
