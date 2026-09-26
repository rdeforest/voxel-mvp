# FillVoxel's `hit + n*0.5` picks the wrong cell on negative faces

**Status:** **CLOSED — not a bug** (2026-09-26). Split out of `misc-low-severity` (item 2) to close it.
Closed by reasoning about the formula, backed by the census in
[single-voxel-edits-unexpected](../single-voxel-edits-unexpected.md) (see *Measured* below).

*Closing note drafted by Claude (agent), 2026-09-26 overnight session. Robert has not reviewed it.*

## The report (code review 2026-06-22)

`ActionFactories.make_fill_voxel` targets `floor(hit + hit_normal*0.5)`, while EmptyVoxel, the probe
and the grid overlay step `VoxelConstants.SURFACE_NUDGE` (0.01). The report said the 0.5 "lands
exactly on a cell boundary", and `floori` of an exact integer picks the higher cell, so it could pick
the wrong cell on `-x/-y/-z` faces. Proposed fix: use the shared nudge.

## Why it's not a bug

- **A tie needs the hit exactly on a cell's sample point.** `floor(h + 0.5)` is only at an integer
  when `h` is a half-integer, which is where `VoxelUtils.sample_point` puts a cell's centre.
  `TerrainRaymarch` bisects a continuous field, so its hit lands exactly there only by coincidence.
  Single-cell edits also keep centres off zero: they set a centre to ±`CELL_EDIT_SDF`, never 0.
- **The 0.5 is the sample-point half-cell, not a stray literal.** Take a flat surface at height `h`
  with normal `+y`. `k = floor(h + 0.5)` picks the cell whose centre `k + 0.5` lies in `(h, h+1]`.
  That is the first cell above the surface whose centre is air. With normal `-y` (a ceiling),
  `floor(h - 0.5)` picks the cell whose centre lies in `(h-1, h]`: the first cell below whose centre
  is air (a centre at exactly `h` reads 0, which is air: solid is strictly `sdf < 0`, per
  `TerrainProbe.is_solid` / `VoxelConstants.SDF_SOLID_THRESHOLD` and the C++ `SOLID_THRESHOLD` in
  `engine/voxel_dc/edit_store_lattice.h`). So away from a tie, the formula picks the
  adjacent air cell on either face.
- **At an exact tie, the bias is on the `+` face, not the `-` face.** On a `+` face, a centre exactly
  at `h` is air but `floor` skips it for the next cell out. On a `-` face the tie picks the right cell.

## Measured

The single-voxel census ran this exact formula (`floor(hit + n*0.5)`) through the real
`TerrainRaymarch` on the real EditStore field. If negative faces systematically picked the solid
cell, those fills would refuse "already solid". They don't: 169 of 4000 aimed fills (4.2 %) refused,
and 1 of 12 on the `cave_ceiling` class (downward-facing surfaces dug with the real `DigAction`).
Two limits on that evidence: the 4000-click census aims mostly at open terrain, so the ceiling case
rests on 12 targets; and raymarch normals are field gradients, not axis-aligned faces, so
"negative face" there means "normal pointing mostly down".

## What the proposed fix would do instead

`floor(hit + n*0.01)` is the cell the hit point sits in, which is roughly the cell the grid overlay
highlights. That is a different target, not a corrected one. It is the open question 2 in
[single-voxel-edits-unexpected](../single-voxel-edits-unexpected.md): should FillVoxel fill the
highlighted cell or the air cell beside it? A guess that hasn't been measured: that cell's centre
would be solid about as often as EmptyVoxel's mirror-image target is air (48 % "already air" in that
file's census). If so, FillVoxel would refuse "already solid" about that often.
