# DigAction: validate() always true, preview disagrees, no player-safety guard

**Status:** **CLOSED — moot under directives** (2026-09-27). The validate/preview half was fixed
2026-09-26; the player-safety guard will not be added, by Robert's decision (see *Verdict* at the
end).
Diagnosed by code review on 2026-06-22.

## Symptom
- Dig over pure air shows a "refused" (greyed) ghost but still executes the carve.
- Digging the floor out from directly under the player is permitted — no clearance/burial guard, unlike
  every sibling additive action.

## Cause
`scripts/actions/dig_action.gd:25` — `validate()` returns `true` unconditionally, while `preview()` sets
`p.refused = p.is_empty()` (`:44`). The ghost computes refusal; the action ignores it.

Separately, Dig has **no** `PlayerSafeAction` check. Bell, Flatten, and CSG all call `endangered_by()`
before mutating; Dig does not. So the refuse-don't-deform contract is only half-applied here.

## Proposed fix
Make `validate()` mirror the preview: refuse when the carve set is empty. Decide explicitly whether Dig
should also refuse when it would drop the player (probably yes for consistency; if "dig anywhere" is a
deliberate affordance, document that instead). Either way, ghost and action must agree.

## References
`scripts/actions/dig_action.gd`; `scripts/actions/player_safe_action.gd` (the guard the siblings use).

## State (2026-09-26, drafted by Claude)

*Drafted by Claude (agent) during the 2026-09-26 overnight session (Track B2). Robert has not reviewed it.*

- **Done.** `validate()` refuses a carve that flips no cell, the same test `preview()` already used, so
  ghost and action agree. The stamped lattice is cached per action (one stamp for validate + execute).
  Pinned by `test/test_player_safe_edits.gd`.
- **Open: the player-safety guard.** The intent looks settled by the code: `PlayerSafeAction`'s contract
  says a player edit must never "carve the ground from under their feet", `LowerAction` (subtractive)
  already refuses that, EmptyVoxel now does, and nothing in the docs asks for "dig anywhere". It was not
  landed because it needs a change to `preview()`, which the overnight track split reserved for the
  preview-in-C++ track. Landing the guard in `validate()` alone would make an unrefused ghost whose click
  does nothing, a new ghost/action disagreement. The whole change, to land together:
  - `extends PlayerSafeAction`; `player = p_ctx.player` in `_init`.
  - `validate()`: also refuse when `endangered_by(_stamp(), store)`.
  - `preview()`: `p.refused = not validate()` (as FillAction and EmptyVoxelAction do), replacing
    `p.refused = p.is_empty()`.
  - Test: the make_dig brush at the player's own column is allowed with nobody near, refused under a
    standing player, allowed with the player 10 m away.
- **Play consequence of the guard.** `make_dig` centres a radius-3 sphere 1.5 m below the hit, and edit
  reach is 30 m. With the player standing on the surface, `scripts/dev/probe_dig_safety_reach.gd` (asks
  `endangered_by` only, stepping the hit 0.1 m outward) finds the brush endangers the player out to
  4.4 m, 4.4 m and 4.7 m from the feet at three columns. At column (100,100) the run is not contiguous:
  endangered to 3.3 m, then again at 4.4 m. Measured headlessly, not tried in play. Whether a ~4.5 m
  no-dig ring feels right is Robert's call.

## Verdict (2026-09-27)
*Recorded by Claude from Robert's answer to the 2026-09-26 brief's question 4
([`overnight-2026-09-26.md`](../../roadmap/implementation/done/overnight-2026-09-26.md), "Needs you
first").*

Keep Dig as "dig anywhere"; no player-safety guard. Robert's reasons:

- Players will reasonably expect to dig under themselves. In real life you dig around yourself and
  move to expose the ground you're standing on.
- Today's Dig is a testing verb with a deliberately huge reach and radius. In the game, digging is
  less dramatic and is expressed as a directive ("make this space empty"); the avatar moves itself as
  needed to carry it out, so the question of digging out from under your own feet goes away.

So this is closed as moot under directives rather than fixed. Doc 22's instrument layer takes over
the exact-control role, bypassing player safety by design. The *State* section's guard spec and the
~4.5 m no-dig ring measurement are kept for the record. `DigAction`'s header says why it isn't a
`PlayerSafeAction`, and `docs/CODE-MAP.md` ("Refuse-don't-deform") points here.
