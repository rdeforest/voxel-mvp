# MPM: `Mat3::svd` loses U's orthonormality as F approaches singular

*Drafted by Claude, 2026-09-26 (overnight Track B5), from measurement; updated by Claude
2026-09-27 (overnight Track E1) with the rank ≤ 1 fix and the in-sim measurement.*

**Status:** open, found while pinning the signed-SVD convention. The rank ≤ 1 part is fixed (below).
The ill-conditioning is left to the fast-SVD rewrite (doc 12), per Robert's answer to Q9: the game's
thaws measured nowhere near it (see "Does the sim get there?"). It is the acceptance bar for that
rewrite, and `test_mpm_svd.gd::test_severely_near_singular` is the pending test the rewrite should
turn on.

## Symptom
Measured with `scripts/dev/probe_svd_cases.gd` (`F = R·diag(1, 1, ±ε)·Rᵀ`, R a fixed non-axis
rotation). Reconstruction stays at ~1e-16 throughout, so only the invariants show the damage:

| ε | det U (+ε / −ε) | \|σ₂\| relative to ε |
|---|-----------------|--------------------|
| 1e-3 | 1 − 5e-11 / 1 − 3e-11 | off by 5e-11 |
| 1e-4 | 1 + 3.5e-9 / 1 + 1.5e-9 | off by 3.5e-9 |
| 1e-5 | 1 + 2.5e-7 | off by 2.5e-7 |
| 1e-7 | 0.9974 / 0.9993 | off by 2.6e-3 |
| 1e-8 | 0.925 / 0.798 | off by 8 % / 25 % |
| 1e-9 | 0.158 / 0.093 | 6× / 11× too large |
| 1e-12 | 1.6e-4 / 1.6e-4 | ~6000× too large |

Two further breaks:

- **Reflection dropped at σ ≤ 1e-12.** `R·diag(1, 1, −1e-12)` (no Rᵀ) returns σ₂ = +1e-12 with
  det F < 0: at σ ≤ 1e-12 the routine builds U's last column as the cross product of the other
  two, which is always right-handed, so the U flip that should carry the reflection never fires.
- **Rank ≤ 1 gave a singular U — fixed 2026-09-27.** `diag(1, 0, 0)` and the zero matrix returned
  det U = 0: filling column 1 read column 2 before it was written, an uninitialized read
  (MemorySanitizer reports it on the old routine). `svd` now fills U's columns in order and
  completes the ones F gives no direction (σ ≤ 1e-12, a suffix since σ is sorted) to a right-handed
  orthonormal basis, so no column is read before it is written. `test_rank_one` and
  `test_rank_zero` fail on the old routine (det U = 0, ‖UᵀU − I‖ = √2 and √3) and pass now;
  `test_rank_two` guards the unchanged rank-2 path. `Mat3` still has no constructor: a zeroing
  one measured about 1.5 % slower per MPM step (interleaved runs of the probe below, e.g. the
  2048-particle drop at 13.48 → 13.68 ms), and with the fill order fixed nothing reads an
  unwritten entry. MPM is `Mat3`'s only user (the DC QEF uses its own arrays), so that cost is
  engine-wide as of 2026-09-27.

`test_mpm_svd.gd` asserts at 1e-9 down to ε = 1e-3, where the routine holds, and on exactly
rank-deficient inputs. A rotated rank-deficient input (`R·diag(1, 0, 0)·Rᵀ`) is not exactly rank
deficient in floating point: its small σ come out near 1e-8, not 0, so it belongs to the
ill-conditioned table, not the fixed case.

## Cause
σ comes from the eigenvalues of FᵀF, which squares F's condition number. The smallest eigenvalue
carries an absolute error of about ε_mach·σ₀², so σ₂ = sqrt(λ₂) has a relative error of about
ε_mach·(σ₀/σ₂)² — the right-hand column above. U's last column is `F·v₂ / σ₂` and inherits that
error, so it isn't unit length and det U drifts by the same factor. At σ₂/σ₀ ≈ 1e-8 that is O(1).

## Does the sim get there?
`MpmSim.get_min_sigma_ratio()` is the smallest |σ₂|/σ₀ any SVD in the sim has seen since
`reset_min_sigma_ratio()`. It covers all three call sites: the elastic and sand constraint targets
(on the candidate F\* = (I + D)·F) and the integration (on the new F, before its σ clamp).
`scripts/dev/probe_mpm_conditioning.gd` runs the scenarios below. The game-path rows go through
`MpmStructure` (its damping, friction and re-centring) at the game's fixed 1/60 s physics tick until
they freeze or 3000 ticks pass; the stress rows step a bare `MpmSim` at the dt shown.

| Path | Scenario | min \|σ₂\|/σ₀ |
|------|----------|---------------|
| game | terrain sphere thaw r = 3, r = 5, r = 3 on a slope | 0.93, 0.88, 0.95 |
| game | floating 9³-cell block (729 cells, 5832 particles), 30 m up | 0.1997 |
| game | floating 3³-cell block (27 cells, 216 particles), 30 m / 80 m up | 0.65002 / 0.65002 |
| stress | sand column 4×10×4 as placed, dt 0.02, viscosity 0 / 0.1 | 0.82 / 0.88 |
| stress | elastic drop (GUT's block) at dt 1/60, 0.05, 0.1, 0.2 | 0.69, 0.33, 5.7e-3, **0** |

The floating blocks' minimum is the landing (about 22 ticks after contact); before contact the ratio
is exactly 1. The 30 m and 80 m rows agree because `MpmStructure`'s damping (0.03 per step) caps the
fall at a terminal g·dt/0.03 ≈ 5.4 m/s, reached about 6 m into the fall, so both land at the same
speed: drop height doesn't reach the impact. None of the floating blocks froze within 3000 ticks —
they slide down the slope near the origin (no tunnelling); that's a separate physics question,
not this bug. The sand rows are an untuned column stepped as placed (the repose-pile test has been
pending since the PB-MPM conversion), not a settled pile.

**Real play stays above 0.19**, three orders of magnitude clear of the 1e-4 where U starts to
drift. That margin is the damping's terminal speed at the fixed 1/60 s tick, not a property of the
thaws. The game can't pass a larger dt today: Godot's `_physics_process` delta is fixed (a hitch
runs more ticks, not a longer one), and nothing sets `Engine.time_scale` or
`physics_ticks_per_second`. Only large timesteps get close: at dt = 0.1 the landing reaches 5.7e-3, and at dt = 0.2
(GUT's `test_unconditional_stability_at_large_timestep`) the constraint's candidate F\* collapses
the vertical axis outright (σ₂ ≈ 1e-24, then exactly 0) when the block hits the floor. That
input is exactly rank 2, which takes the cross-product path, not the ill-conditioned one. Before
the fix above, a rank ≤ 1 F\* would have read uninitialized memory in that test.

## Proposed fix
The McAdams-2011 rewrite (doc 12), which gets U by QR of F·V (Givens), not by dividing by σ. When
it lands, replace the `pending` with assertions over the table in Symptom. The measurement says
the rest can wait for it: the game's thaws never approach the bad region. Re-measure if anything raises the
impact speed or the step: lower damping, an MPM tick past ~0.05 s (or a raised `Engine.time_scale`
/ lowered physics tick rate), or thaws that start with velocity. Higher drops alone don't.

The reflection dropped at σ ≤ 1e-12 is still open. The dt = 0.2 landing does reach σ₂ ≤ 1e-12,
but there det F\* is ±1e-32 or zero, so its sign carries no information either way. The −ε rows of
the Symptom table are the rewrite's check for it.
