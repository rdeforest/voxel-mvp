# MPM: SVD double reflection-flip corrupts σ₂ sign for inverted elements

**Status:** Deferred (2026-06-22). Diagnosed by code review of the SVD math; not reproduced (and the current
test *cannot* catch it — see below). Real but rarely triggered (gravity settling seldom inverts elements).

## Symptom (expected)
For a deformation gradient F containing a genuine reflection (`det F < 0`), the polar rotation
`R = U·Vᵀ` used as the elastic restoring target comes out as a pure rotation with the inversion thrown
away → wrong restoring force for inverted/reflected elements.

## Root cause (precise)
`engine/voxel_dc/mat3.cpp:201-213`. The reflection-absorption negates σ₂ **independently** for V and for U:

```
if (v.determinant() < 0.0) { flip v col2; ss[2] = -ss[2]; }
if (u.determinant() < 0.0) { flip u col2; ss[2] = -ss[2]; }
```

The eigen routine builds U from `F·V`, so a reflected V drags U's determinant negative with it — meaning for
a genuinely reflected F **both** `if`s fire. σ₂ is negated twice → back to positive, while both U and V have
had their 3rd column flipped. The reconstruction `U·diag(σ)·Vᵀ` still equals F (the two column flips cancel),
but the **signed-SVD invariant is violated**: you now have `det(U)=det(V)=+1` with σ₂ > 0, which can only
represent a rotation, not the reflection F actually held. Downstream `_constraint_target`
(`mpm_material.cpp:30`) then uses the wrong rotation for inverted elements.

The correct rule negates σ₂ **once**, tracking a single parity so that `sign(σ₂)` follows `sign(det F)`:
the both-negative case flips a column of both U and V and leaves σ unchanged; the single-negative cases
flip the smallest-σ column and negate that σ.

## Why the existing test is blind to it
`Mat3::debug_svd` (`engine/voxel_dc/mpm_sim.cpp:349-359`) only checks reconstruction error
`‖U·diag(σ)·Vᵀ − F‖`, which stays ~0 because the double flip cancels. The dict already exposes
`det_u`, `det_v`, `s2` — the test just never asserts on them.

## Proposed fix
Rewrite the reflection step to a single-parity form. Add a test case feeding a known reflection matrix
(`det F < 0`) and asserting `det(U)·det(V) == sign(det F)` and `σ₂ < 0`.

## References
`engine/voxel_dc/mat3.cpp` `Mat3::svd`; `engine/voxel_dc/mpm_material.cpp` `_constraint_target`;
`engine/voxel_dc/mpm_sim.cpp` `debug_svd`. PB-MPM (Lewin 2024), signed-SVD convention.
