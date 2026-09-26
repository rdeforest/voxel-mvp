# MPM: SVD double reflection-flip corrupts σ₂ sign for inverted elements

**Status:** **CLOSED — not a bug.** Reported 2026-06-22 from a code read, refuted 2026-09-25 from a
code read. The code in `Mat3::svd` is correct. Archived because the reasoning error is an easy one to
make twice — this is the second time the reflection handling has been flagged.

*Refutation drafted by Claude, 2026-09-25, at Robert's request.*

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
