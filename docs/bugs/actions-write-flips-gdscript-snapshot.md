# A write's flips are measured in GDScript around it (~1.3 ms per placement)

*Filed by Claude (agent), overnight 2026-09-26, while closing Track G1 (lattice material paint in C++).*

**Status:** Open. Severity low (perf; ~1.3 ms of a ~1.8 ms placement against a 20 ms frame, on the
frame the player commits).

## Symptom
`ConstructionAction.execute()` for the beam on the game store costs ~1.8 ms
(`scripts/dev/bench_construction_execute.gd`, 200 reps, fresh store per rep; CSG box/sphere ADD and
SUBTRACT the same, fill / dig r2 ~0.37 ms). Splitting one `VoxelImprint.apply` (throwaway probe, 200
reps, beam resting, yaw 0):

| stage | ms |
|-------|----|
| `VoxelImprint.lattice` (C++ `predict_imprint`) | 0.074 |
| `SdfLattice.materials` (C++ `lattice_materials`) | 0.036 |
| `CellFlips.snapshot` (1728 cells) | 0.580 |
| `SdfLattice.write` | 0.166 |
| `CellFlips.since` | 0.722 |

## Cause
`CellFlips.snapshot`/`since` are two passes of per-cell `store` queries from GDScript over every cell the
write can change.

## Options
- Fold the measured flips into the C++ write (return solid/air flips from the write itself), which
  removes the snapshot/since round-trips and keeps `apply`'s single-measurement contract. FillAction and
  DigAction measure the same way and would take the same path.
- Leave it: under budget.

## History
Split from `actions-imprint-materials-gdscript-per-point` (fixed, deleted), filed at ~6.0 ms per beam placement, ~4.3 ms of it `SdfLattice.materials`: a GDScript loop over every
lattice point (13³ for the beam) calling a brush-solid `Callable` (GDScript `shape.sdf` behind an affine
inverse) and `store.sample_toward`, then every cell's 8 corners with `store.material_at`. Track G1 moved
it to C++: the brush builders (`predict_sphere_stamp`, `predict_imprint`) record per point whether the
write made it solid (`made`, from the brush value and owner-leaf "before" they already combine), and
`EditStore.lattice_materials` paints from that; the GDScript original is the oracle
(`test/support/lattice_oracle.gd`) of the gate `test_lattice_materials_predict` plus the max-face seams in
`test_lattice_materials`. Beam execute() 6.3 → 1.8 ms, CSG box ADD 6.6 → 1.8 ms, SUBTRACT 5.5 → 1.8 ms,
fill r2 1.33 → 0.38 ms, dig r2 1.15 → 0.36 ms.
