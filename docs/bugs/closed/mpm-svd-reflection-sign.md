# MPM: SVD double reflection-flip corrupts σ₂ sign for inverted elements

**Status:** **CLOSED — not a bug.** Reported 2026-06-22 from a code read, refuted 2026-09-25 from a
code read. The code in `Mat3::svd` is correct. Archived because the reasoning error is an easy one to
make twice — this is the second time the reflection handling has been flagged.

*Refutation drafted by Claude, 2026-09-25, at Robert's request.*

**Regression test now exists (2026-09-26):** `test/test_mpm_svd.gd` asserts det U = det V = +1,
reconstruction and sign(σ₂) = sign(det F) on inputs that reach every row of the table below. Which
input reaches which row is at the end of this file. *(Line and section drafted by Claude.)*

## Verdict first

The report claims both reflection `if`s fire for a genuinely reflected F. They don't: a reflected F
fires **exactly one**. The both-fire case is `det F > 0` with an arbitrarily-signed V, and there the
double-negate is exactly right. The signed-SVD invariant holds in all four cases.

If you are re-reading `mat3.cpp` and the two independent `ss[2] = -ss[2]` look wrong, work the table
below before writing it up.

## Why the double-negate is correct

U is built as `F·V·Σ⁻¹` with σᵢ ≥ 0 (they come from eigenvalues of FᵀF), so
`sign(det U) = sign(det F) · sign(det V)`. V's own sign is whatever the eigen routine happened to
produce. That gives four cases, and the two `if`s dispatch on them correctly:

| det F | det V | det U | which `if`s fire | resulting σ₂ | correct? |
|-------|-------|-------|------------------|--------------|----------|
| +     | +     | +     | neither          | > 0          | yes |
| +     | −     | −     | **both**         | > 0 (flips cancel) | yes — F is a rotation |
| −     | +     | −     | U only           | < 0          | yes |
| −     | −     | +     | V only           | < 0          | yes |

In every row the result is `det U = det V = +1` with `sign(σ₂) = sign(det F)` — the signed-SVD
convention the downstream polar rotation needs. In the both-fire row the two column flips cancel *and*
so do the two σ₂ negations, which is the point: that row is a proper rotation wearing a sign-flipped V.

The report reached the opposite conclusion by assuming the both-fire case corresponds to reflected F.
It corresponds to `det F > 0`.

## What was right in the report, and survives

**The test is blind, and that part still stands.** `Mat3::debug_svd`
(`engine/voxel_dc/mpm_sim.cpp`) asserts only reconstruction error `‖U·diag(σ)·Vᵀ − F‖`, which stays
~0 under *any* even number of cancelling flips — including genuinely broken ones. The dict already
exposes `det_u`, `det_v` and `s2`; nothing asserts on them.

So a real regression test is still worth writing, not to fix today's code but to pin it:

- feed a known reflection (`det F < 0`)
- assert `det(U) · det(V) == +1` and `σ₂ < 0`
- feed a rotation with a sign-flipped V and assert `σ₂ > 0`

Write it **before** the McAdams-2011 fast-SVD rewrite (doc 12's next step), which will replace this
routine wholesale and has every opportunity to get the parity wrong for real. That is tracked in
`docs/STATUS.md` under the MPM paused thread.

## Which test input reaches which row

Classified with `scripts/dev/svd_branch_port.py`, a line-for-line Python port of `Mat3::svd` fed the
exact matrices the tests build (dumped by `scripts/dev/dump_svd_random_inputs.gd`, which also prints
the engine's `debug_svd` output on each). On all 121 inputs the port's det U, det V, σ and
reconstruction error agree with the engine's to within 7e-16 on the fixed inputs other than
R·diag(1, 1, 1e-3)·Rᵀ (4e-11), and within 1.1e-13 on the random ones. `debug_svd` only reports values
after the flips, so this checks the arithmetic, not the branch directly.

Row membership is exact only where the spectrum is well separated: there det V before the flips is
the parity of the sort permutation (Jacobi rotations have det +1), so the axis-aligned diagonal
inputs land in their rows by construction — diag(2, 1, 0.5) none, diag(0.5, 1, 2) both,
diag(2, 1, −0.5) and −I U, diag(−0.5, 1, 2) and diag(1, −2, 0.5) V. Where FᵀF has repeated or nearly
repeated eigenvalues (R, the Euler rotation, the repeated-σ and near-singular inputs), the sort order
is decided by rounding noise, and their rows below are what the port reports today, not a stable fact.
The assertions don't depend on which row an input lands in.

| Row (det F, det V before the flips) | Inputs in `test_mpm_svd.gd` |
|-----|-----|
| +, + (neither flip) | diag(2, 1, 0.5), diag(1, 0.5, 2), identity, R·diag(2, 2, 0.5)·Rᵀ, R·diag(1, 1e-3, 1e-3)·Rᵀ |
| +, − (both flip) | pure rotation R, diag(0.5, 1, 2), R·diag(0.5, 1, 2), R·diag(2, 1, 0.5), the Euler rotation and its scaling, R·diag(2, 0.5, 0.5)·Rᵀ, R·diag(1, 1, 1e-3)·Rᵀ, 32 of the 64 random U·Σ·Vᵀ, 15 of the 32 random-entry matrices |
| −, + (U flips) | diag(2, 1, −0.5), diag(−1, 0.5, 2), −I, R·diag(1, 1, −1e-3)·Rᵀ |
| −, − (V flips) | diag(−0.5, 1, 2), diag(1, −2, 0.5), R·diag(2, 1, −0.5), R·diag(−0.5, 1, 2), the Euler reflection, R·diag(2, 0.5, −0.5)·Rᵀ, R·diag(1, 1, −1)·Rᵀ, −R, 32 of the 64 random U·Σ·Vᵀ, 17 of the 32 random-entry matrices |

The same port, run with the reflection block replaced, shows what each wrong version fails:

- **The report's rule as written** (both negative: flip both columns, leave σ; one negative: flip
  it and negate σ₂) passes everything. It is the current code: two negations of σ₂ cancel. The
  report was wrong about which F reaches the both-flip row, not about the flips.
- **The fix the report's diagnosis leads to** (negate σ₂ once whenever any column flips, so a
  "reflected" both-flip row keeps σ₂ < 0) fails reconstruction, sign(σ₂) = sign(det F) and Πσ =
  det F on every both-flip input (55 of the 121). Only that row catches it, which is why the pure
  rotation and diag(0.5, 1, 2) are in the tests.
- **A missing V flip** fails det V = +1, sign(σ₂) = sign(det F) and Πσ = det F on every both-flip
  and V-flip input. **A missing U flip** fails the same three, with det U, on every both-flip and
  U-flip input. **No flips at all** fails det U and det V on the both-flip inputs, and the
  determinant, sign and Πσ checks on the single-flip ones.
- The report's own proposed assertion, det(U)·det(V) == sign(det F), would fail on the *correct*
  code for every reflection. The tests assert det U = det V = +1 instead.

## References

`engine/voxel_dc/mat3.cpp` `Mat3::svd` (the reflection-absorption block at the end);
`engine/voxel_dc/mpm_material.cpp` `_constraint_target`; `engine/voxel_dc/mpm_sim.cpp` `debug_svd`.
PB-MPM (Lewin 2024), signed-SVD convention.

---

## The original report, preserved

*Everything below is the 2026-06-22 text as filed. It is wrong; it is kept so the refutation above has
something to point at.*

> **Status:** Deferred (2026-06-22). Diagnosed by code review of the SVD math; not reproduced (and the
> current test *cannot* catch it — see below). Real but rarely triggered (gravity settling seldom
> inverts elements).
>
> ### Symptom (expected)
> For a deformation gradient F containing a genuine reflection (`det F < 0`), the polar rotation
> `R = U·Vᵀ` used as the elastic restoring target comes out as a pure rotation with the inversion
> thrown away → wrong restoring force for inverted/reflected elements.
>
> ### Root cause (precise)
> `engine/voxel_dc/mat3.cpp:201-213`. The reflection-absorption negates σ₂ **independently** for V and
> for U:
>
> ```
> if (v.determinant() < 0.0) { flip v col2; ss[2] = -ss[2]; }
> if (u.determinant() < 0.0) { flip u col2; ss[2] = -ss[2]; }
> ```
>
> The eigen routine builds U from `F·V`, so a reflected V drags U's determinant negative with it —
> meaning for a genuinely reflected F **both** `if`s fire. σ₂ is negated twice → back to positive,
> while both U and V have had their 3rd column flipped. The reconstruction `U·diag(σ)·Vᵀ` still equals
> F (the two column flips cancel), but the **signed-SVD invariant is violated**: you now have
> `det(U)=det(V)=+1` with σ₂ > 0, which can only represent a rotation, not the reflection F actually
> held. Downstream `_constraint_target` (`mpm_material.cpp:30`) then uses the wrong rotation for
> inverted elements.
>
> The correct rule negates σ₂ **once**, tracking a single parity so that `sign(σ₂)` follows
> `sign(det F)`: the both-negative case flips a column of both U and V and leaves σ unchanged; the
> single-negative cases flip the smallest-σ column and negate that σ.
>
> ### Why the existing test is blind to it
> `Mat3::debug_svd` (`engine/voxel_dc/mpm_sim.cpp:349-359`) only checks reconstruction error
> `‖U·diag(σ)·Vᵀ − F‖`, which stays ~0 because the double flip cancels. The dict already exposes
> `det_u`, `det_v`, `s2` — the test just never asserts on them.
>
> ### Proposed fix
> Rewrite the reflection step to a single-parity form. Add a test case feeding a known reflection
> matrix (`det F < 0`) and asserting `det(U)·det(V) == sign(det F)` and `σ₂ < 0`.
