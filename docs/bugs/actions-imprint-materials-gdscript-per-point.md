# A placement spends ~4.3 ms painting materials in GDScript

*Filed by Claude (agent), overnight 2026-09-26, while closing Track C2 (`VoxelImprint.apply` returns
its measured flips).*

**Status:** Open. Severity low-med (perf; ~6 ms per placement against a 20 ms frame, on the frame the
player commits). Needs a call on the fix's shape.

## Symptom
`ConstructionAction.execute()` for the beam on the game store costs ~6.0 ms
(`scripts/dev/bench_construction_execute.gd`, 200 reps, fresh store per rep). Splitting one
`VoxelImprint.apply` (throwaway probe, 100 reps, beam resting, yaw 0):

| stage | ms |
|-------|----|
| `VoxelImprint.lattice` (C++ `predict_imprint`) | 0.072 |
| `SdfLattice.materials` | 4.335 |
| `CellFlips.snapshot` (1728 cells) | 0.573 |
| `SdfLattice.write` | 0.169 |
| `CellFlips.since` | 0.723 |

`CsgAction.execute()` goes through the same `apply`, so a CSG ADD/SUBTRACT pays the same shape of cost.

## Cause
`SdfLattice.materials` (`scripts/actions/sdf_lattice.gd`) loops over every lattice point (13³ for the
beam) in GDScript, calling the brush-solid `Callable` (a GDScript `shape.sdf` behind an affine inverse)
and `store.sample` per point, then a second pass over every cell's 8 corners with `store.material_at` for
kept cells. The per-point interpreter + Callable overhead is the cost, not the store reads.

`CellFlips.snapshot`/`since` add ~1.3 ms more: two passes of per-cell `store` queries from GDScript.

## Options
- Port the material paint to `EditStore` alongside `predict_imprint`, taking the brush as data (shape
  kind + dimensions + transform, as `predict_imprint` already does) instead of a Callable. The brush
  SDF mirror (box/cylinder/sphere from `sdf_kind()`/`sdf_dims()`) already exists for `predict_imprint`.
- Fold the measured flips into the same C++ write (return solid/air flips from the write itself), which
  removes the snapshot/since round-trips and keeps `apply`'s single-measurement contract.
- Leave it: under budget, but a third of the frame on commit.
