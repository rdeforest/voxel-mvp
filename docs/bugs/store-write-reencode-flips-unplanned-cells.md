# StoreWrite's box rewrite flips cells nobody edited

*Filed by Claude (agent) on 2026-09-27, carrying the non-thaw half of the fixed bug
`mpm-thaw-carve-leaves-planned-cells` ("Separate effect").*

**Status:** Open. Severity low: fixed for the thaw (F1) and for single cells; the other box writers
still do it.

## Symptom
A StoreWrite box write rewrites every corner in its box from the field's own corner samples. The
generated field's value at a cell centre is not the trilerp of its corners, so the rewrite alone can
flip cells the edit never named. Measured on the thaw before F1: 17 cells to air and 1 to solid over
190 small terrain thaws, one of them about 3 m outside a radius-1.4 sphere. The flips are measured
and announced, so nothing is hidden, but matter moves that nobody asked to move.

## Where it is and isn't
- **Repaired:** the MPM thaw (`EditStore.predict_carve` keeps every unplanned cell on its side;
  doc 12, "The thaw carve") and `StoreWrite.one_cell` (FillVoxel/EmptyVoxel; its LP keeps all 26
  neighbours on their side).
- **Still exposed:** Bell and Flatten (`StoreWrite.reshape` on the predicted lattice); Fill, Dig,
  CSG and `VoxelImprint` (`SdfLattice.write`); the instruments SetCorners and SetMaterial
  (`StoreWrite.lattice`/`write`), whose comments describe it as accepted behaviour; and the MPM
  freeze's 1 m rewrite (whose flips aren't even measured yet: `mpm-freeze-flips-unmeasured`).

## Decision so far
Robert agreed (Q3 of the 2026-09-26 questions) to "repair it, inside the same solve as question 2".
That was done for the thaw only. Open question for him: should every box writer get the same
keep-your-side constraint (a shape edit would then constrain the cells outside its intended change),
or only material-only writes like SetMaterial, where any flip is plainly unintended?

## Proposed fix
Pose the other writers' boxes to the same constrained solve `predict_carve` uses: the cells the edit
means to change get their target side, every other rewritten cell keeps its current side, refuse
where no field does both.
