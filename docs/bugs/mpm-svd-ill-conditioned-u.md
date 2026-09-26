# MPM: `Mat3::svd` loses U's orthonormality as F approaches singular

*Drafted by Claude, 2026-09-26 (overnight Track B5), from measurement.*

**Status:** open, found while pinning the signed-SVD convention. Latent: nothing shows the sim
reaching these deformations today. It is the acceptance bar for the fast-SVD rewrite (doc 12), and
`test_mpm_svd.gd::test_severely_near_singular_and_rank_deficient` is the pending test that rewrite
should turn on.

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
- **Rank ≤ 1 gives a singular U.** `diag(1, 0, 0)` and the zero matrix return det U = 0. Filling
  column 1 reads column 2, which hasn't been written yet: `Mat3` has no constructor, so that is an
  uninitialized read. It happened to be zero here; in principle it is undefined behaviour.

`test_mpm_svd.gd` asserts at 1e-9 down to ε = 1e-3, where the routine holds.

## Cause
σ comes from the eigenvalues of FᵀF, which squares F's condition number. The smallest eigenvalue
carries an absolute error of about ε_mach·σ₀², so σ₂ = sqrt(λ₂) has a relative error of about
ε_mach·(σ₀/σ₂)² — the right-hand column above. U's last column is `F·v₂ / σ₂` and inherits that
error, so it isn't unit length and det U drifts by the same factor. At σ₂/σ₀ ≈ 1e-8 that is O(1).

## Proposed fix
The McAdams-2011 rewrite (doc 12), which gets U by QR of F·V (Givens), not by dividing by σ. When
it lands, replace the `pending` with assertions over the table above and the rank-deficient inputs.
If the old routine has to live longer, the smaller fix is to build U's smallest column from the
cross product of the two larger ones whenever σ₂/σ₀ is below ~1e-4, and give `Mat3` a zeroing
constructor or zero `u` before filling it.

Whether the sim can reach σ₂/σ₀ < 1e-4 at all is unmeasured. `_constraint_target` clamps only the
volume term (`|det F|` to [0.1, 1000]), not F.
