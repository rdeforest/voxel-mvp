# FillVoxel / EmptyVoxel don't do what Robert expected in play (known unknown)

*Filed by Claude (agent) on 2026-09-25, from the agent review loop that fixed sdf-sample-corner-vs-center and actions-untyped-work-tuple.*

**Status:** Open, **re-scoped 2026-09-27**: superseded by doc 22's instrument layer, and closes when
that layer ships (overnight 2026-09-27 chunk G4.4). Robert answered the questions; see *Robert's
answers* at the end. Characterized 2026-09-26 (section below). Robert tried single-voxel edits
in-game after `f11d284` and `c9430a4` and "didn't get what I expected."

## What the code does now
A "cell" is a 1 m voxel. Its solidity is the trilinear value at its centre, which is the mean of its 8
corner values (`VoxelUtils.sample_point`). Neighbours share those corners: 4 across a face, 2 across an
edge, 1 across a vertex. `StoreWrite.one_cell` (`scripts/actions/store_write.gd:68`) sets up a small
linear program over the target's 8 corner offsets (solved by `scripts/simplex.gd`). It uses the
smallest push that moves the target's mean `CELL_EDIT_SDF` (0.01) past zero while every neighbour's
mean stays on its current side by `CELL_KEEP_SDF`. If no such push exists, the action refuses.

## Hypotheses (agent-generated, unverified)
1. **Gameplay solidity and the rendered surface disagree.** Gameplay asks whether the centre is below
   zero. The DC mesher draws the surface where *corners* change sign, and places it with a QEF. The
   LP only needs the centre 0.01 past zero, so the render may show a small bump or dent instead of a
   1 m cube. Or it may show a surface that moves across neighbours whose corners changed sign even
   though their centres didn't.
2. **Refusal where a cube was expected.** When neighbours sit near zero, no corner push can satisfy
   everyone and the edit refuses. Tests measured 0 refusals in 882 surface placements, but those were
   synthetic.
3. **Material paint.** Only the target cell's leaf gets the material, so the colour may not match the
   geometry that appears.
4. **Expectation mismatch.** Before these commits, FillVoxel/EmptyVoxel made a blob offset half a
   cell. Now they aim at the highlighted cell exactly. The difference itself may be the surprise.

## References
`scripts/actions/fill_voxel_action.gd`, `empty_voxel_action.gd`, `store_write.gd`, `simplex.gd`,
`scripts/voxel_constants.gd` (`CELL_EDIT_SDF`, `CELL_KEEP_SDF`). Related:
[[dc-inside-coverage-cracks]] (how DC places vertices).


## Characterization (2026-09-26, drafted by Claude)

*Drafted by Claude (agent) during the 2026-09-26 overnight session. Evidence only; no action code
was changed. Robert has not reviewed it.*

### How it was measured
`scripts/dev/probe_single_voxel.gd` is the entry point, with `single_voxel_targets.gd`,
`single_voxel_probe.gd`, `single_voxel_mesh_diff.gd`, `single_voxel_legacy.gd`,
`single_voxel_occupancy.gd` and `single_voxel_tsv.gd`. Every table and figure below is printed by
`scripts/dev/summarize_single_voxel.py`; none is hand-derived. Deterministic (seed 1337); the probe
takes about 5 minutes, the check about 30 s:

    godot --path . --headless -s res://scripts/dev/probe_single_voxel.gd -- out.tsv 12 4000
    godot --path . --headless -s res://scripts/dev/probe_single_voxel.gd -- check out.occupancy.tsv 12
    scripts/dev/summarize_single_voxel.py out.tsv   # also reads out.census.tsv, out.occupancy.tsv

- **Field.** An `EditStore` set up exactly as `EditStoreManager` does it: the C++ TerrainField
  generator plus sparse multi-level edit leaves. This is the field the game samples today;
  godot_voxel was removed from the game (`docs/roadmap/implementation/done/extras-10-octree-edit-store.md`),
  so no godot_voxel-encoded field exists to test against. Caves and overhangs were dug with the real
  `DigAction` (radius 3, or 2.5 for overhangs), so those targets sit on 1 m edit leaves over the
  generated field.
- **Aim and target.** Same as the game. `TerrainRaymarch.surface` runs from an eye 3.5 m off the
  surface (step 0.2, reach 30), as `player.gd` does. The cell comes from `ActionFactories`' formulas:
  FillVoxel uses `floor(hit + n*0.5)` and EmptyVoxel uses `floor(hit - n*0.01)`. The actions are the
  real `FillVoxelAction` / `EmptyVoxelAction` with no player, so FillVoxel's player-safety refusal
  (`endangered_by`) never fires: the refusal figures cover terrain and LP refusals only. A Fill aimed
  next to the player's body can also refuse in game.
- **Render.** `DCOctreeMesher.mesh_world` is called as `DcWorldPreview` calls it: depth 13, root
  snapped to 64, 1 m base cell, a ±16 m resident window, palette colours. Two modes were meshed.
  *live* is error-driven at eps 0.5 px (EPS_MIN), with proj for a 75° FOV at 1080 lines. *dense* has
  no collapse. Each target was meshed before and after the edit.
- **Geometry diff.** Inside/outside comes from +y ray parity on a 0.1 m grid over the target
  ±2 cells (125 k points). Two guards: a column whose field is still solid at the window's (open) top
  would invert parity, and none did in any mesh; and window vertices outside the ±2 box that moved
  are counted, because the volume diff can't see them (see *Live vs dense*).
- **Sample.** 10 201 columns over 2 km × 2 km, classed by slope and ridge metric (height minus the
  mean of 4 points 4 m away). 12 targets per class went through single, repeat, fill-then-empty and
  adjacent (+1 m x) click sequences. The terrain has no column below the −0.4 m valley threshold
  (the most concave is −0.15 m), so *valley* targets are the 48 most concave columns
  (−0.15 to −0.13 m), spread to 12. A census of 4000 aimed clicks per verb ran `validate()` only.
  The `legacy_*` rows replay the pre-`f11d284` rule on the same aims: solidity read at the min
  corner, and that one lattice point written to ±5. `f11d284` and `c9430a4` did not change the
  factories' cell formulas, so these are the cells the old code targeted.

Definitions: "target solid frac" = fraction of the target cell's volume under the mesh. "dV outside"
= changed volume (m³) in other cells of the ±2 box, a lower bound (see *Live vs dense*).
"neighbours touched" = other cells with ≥ 0.01 m³ changed. "centroid along n" > 0 means the change
sits on the air side, measured from the target centre and, separately, from the aimed hit point
(on the original surface). "cube" = fill leaves the target ≥ 0.9 solid (empty ≤ 0.1) with ≤ 0.25 m³
outside it. "centre flipped" uses the current (cell-centre) definition for every rule, including
legacy, whose own target was the min *corner*.

### Refusals: census, 4000 aimed clicks per verb

| verb | clicks | executes | refused (reason:n) |
|---|---|---|---|
| fill | 4000 | 3831 (95.8 %) | already_solid:169 (4.2 %) |
| empty | 4000 | 2076 (51.9 %) | already_air:1915 (47.9 %), lp_infeasible:9 (0.2 %) |
| legacy_fill | 4000 | 2454 (61.4 %) | already_solid:1546 (38.6 %) |
| legacy_empty | 4000 | 3205 (80.1 %) | already_air:795 (19.9 %) |

- fill: push n=3831 median 0.99 p90 2.06 max 4.30; a corner changes sign in 3471 (90.6 %); LP infeasible by class: -
- empty: push n=2076 median 0.35 p90 0.99 max 3.81; a corner changes sign in 1420 (68.4 %); LP infeasible by class: ridge:9

### Single edits, per terrain class (live mesh)

| verb | class | n | refused (reason:n) | target solid frac before -> after | dV in target | dV outside | centroid off (m) | centroid along n from centre (m) | centroid along n from hit (m) | max surface shift (m) | neighbours touched | target centre flipped | other centres flipped |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| empty | cave_ceiling | 12 | already_air:6 | 0.58 -> 0.37 | 0.23 | 0.64 | 0.28 | 0.26 | 0.12 | 0.34 | 19.00 | 6/6 | 0 |
| empty | cave_floor | 12 | already_air:4 | 0.70 -> 0.42 | 0.27 | 0.83 | 0.45 | 0.41 | 0.19 | 0.40 | 22.00 | 8/8 | 0 |
| empty | cave_wall | 12 | already_air:7 | 0.82 -> 0.47 | 0.32 | 1.14 | 0.51 | 0.49 | 0.19 | 0.92 | 23.00 | 5/5 | 0 |
| empty | flat | 12 | already_air:6 | 0.62 -> 0.48 | 0.13 | 0.55 | 0.15 | 0.08 | -0.05 | 0.20 | 10.50 | 6/6 | 0 |
| empty | gentle | 12 | already_air:5 | 0.80 -> 0.48 | 0.29 | 1.08 | 0.28 | 0.21 | -0.08 | 0.37 | 14.00 | 7/7 | 0 |
| empty | near_zero_empty | 12 | already_air:6 | 0.59 -> 0.50 | 0.07 | 0.36 | 0.29 | 0.06 | -0.02 | 0.15 | 9.50 | 6/6 | 0 |
| empty | overhang_roof | 12 | already_air:4 | 0.79 -> 0.44 | 0.38 | 2.02 | 0.60 | 0.43 | 0.11 | 0.90 | 33.50 | 8/8 | 0 |
| empty | ridge | 12 | already_air:7 | 0.75 -> 0.46 | 0.33 | 1.60 | 0.20 | 0.08 | -0.19 | 0.61 | 17.00 | 5/5 | 0 |
| empty | slope | 12 | already_air:5 | 0.69 -> 0.47 | 0.24 | 0.75 | 0.10 | 0.10 | -0.05 | 0.31 | 13.00 | 7/7 | 0 |
| empty | steep | 12 | already_air:4 | 0.85 -> 0.43 | 0.42 | 1.26 | 0.21 | 0.20 | -0.11 | 0.72 | 15.50 | 8/8 | 0 |
| empty | valley | 12 | already_air:6 | 0.81 -> 0.46 | 0.34 | 1.04 | 0.24 | 0.21 | -0.09 | 0.48 | 15.00 | 6/6 | 0 |
| fill | cave_ceiling | 12 | already_solid:1, lp_infeasible:2 | 0.03 -> 0.49 | 0.46 | 2.52 | 0.32 | -0.15 | 0.44 | 0.67 | 23.00 | 9/9 | 0 |
| fill | cave_floor | 12 | lp_infeasible:1 | 0.00 -> 0.48 | 0.30 | 3.14 | 0.31 | -0.29 | 0.40 | 0.70 | 30.00 | 11/11 | 0 |
| fill | cave_wall | 12 | already_solid:1, lp_infeasible:3 | 0.14 -> 0.51 | 0.38 | 2.06 | 0.30 | -0.06 | 0.35 | 2.06 | 20.50 | 8/8 | 0 |
| fill | flat | 12 | - | 0.01 -> 0.55 | 0.49 | 2.04 | 0.49 | -0.39 | 0.23 | 0.83 | 14.50 | 12/12 | 0 |
| fill | gentle | 12 | - | 0.00 -> 0.56 | 0.44 | 1.87 | 0.44 | -0.38 | 0.23 | 0.81 | 15.50 | 12/12 | 0 |
| fill | near_zero_fill | 12 | already_solid:1 | 0.00 -> 0.48 | 0.48 | 2.46 | 0.36 | -0.35 | 0.26 | 1.09 | 18.00 | 11/11 | 0 |
| fill | overhang_roof | 12 | lp_infeasible:6 | 0.00 -> 0.51 | 0.51 | 4.76 | 0.38 | -0.30 | 0.39 | 0.99 | 40.00 | 6/6 | 0 |
| fill | ridge | 12 | already_solid:1 | 0.01 -> 0.53 | 0.41 | 2.35 | 0.47 | -0.43 | 0.13 | 1.58 | 21.00 | 11/11 | 0 |
| fill | slope | 12 | already_solid:2 | 0.03 -> 0.56 | 0.48 | 2.29 | 0.25 | -0.23 | 0.28 | 1.22 | 19.50 | 10/10 | 0 |
| fill | steep | 12 | already_solid:2 | 0.15 -> 0.55 | 0.40 | 1.28 | 0.24 | -0.20 | 0.12 | 0.76 | 14.50 | 10/10 | 0 |
| fill | valley | 12 | - | 0.05 -> 0.55 | 0.49 | 1.80 | 0.31 | -0.26 | 0.18 | 0.96 | 15.00 | 12/12 | 0 |
| legacy_empty | flat | 12 | - | 0.48 -> 0.23 | 0.26 | 2.03 | 0.88 | -0.54 | -0.52 | 1.32 | 12.50 | 6/12 | 30 |
| legacy_empty | gentle | 12 | - | 0.60 -> 0.29 | 0.26 | 1.79 | 0.83 | -0.47 | -0.51 | 1.16 | 12.50 | 7/12 | 26 |
| legacy_empty | ridge | 12 | already_air:5 | 0.64 -> 0.31 | 0.24 | 1.92 | 0.93 | -0.33 | -0.44 | 1.32 | 13.00 | 4/7 | 12 |
| legacy_empty | slope | 12 | already_air:1 | 0.55 -> 0.21 | 0.28 | 2.06 | 0.80 | -0.50 | -0.35 | 1.37 | 14.00 | 7/11 | 23 |
| legacy_empty | steep | 12 | already_air:3 | 0.85 -> 0.59 | 0.20 | 1.35 | 0.85 | -0.28 | -0.59 | 0.67 | 11.00 | 7/9 | 11 |
| legacy_empty | valley | 12 | already_air:3 | 0.73 -> 0.39 | 0.26 | 2.09 | 0.87 | -0.30 | -0.50 | 1.41 | 14.00 | 6/9 | 17 |
| legacy_fill | flat | 12 | already_solid:6 | 0.00 -> 0.29 | 0.29 | 1.64 | 0.79 | -0.34 | 0.52 | 1.19 | 7.00 | 0/6 | 1 |
| legacy_fill | gentle | 12 | already_solid:5 | 0.00 -> 0.29 | 0.29 | 1.70 | 0.83 | -0.38 | 0.52 | 1.24 | 8.00 | 0/7 | 12 |
| legacy_fill | ridge | 12 | already_solid:4 | 0.01 -> 0.34 | 0.28 | 1.87 | 0.84 | -0.35 | 0.29 | 1.48 | 13.50 | 1/8 | 16 |
| legacy_fill | slope | 12 | already_solid:7 | 0.00 -> 0.35 | 0.28 | 1.46 | 0.85 | -0.20 | 0.28 | 1.25 | 9.00 | 1/5 | 12 |
| legacy_fill | steep | 12 | already_solid:6 | 0.12 -> 0.49 | 0.24 | 1.57 | 0.95 | -0.06 | 0.35 | 1.49 | 11.00 | 3/6 | 9 |
| legacy_fill | valley | 12 | already_solid:4 | 0.01 -> 0.35 | 0.33 | 1.56 | 0.80 | -0.19 | 0.39 | 1.30 | 8.50 | 5/8 | 16 |

The legacy rows' "target centre flipped" and "other centres flipped" are measured against today's
centre definition. The old rule aimed at the min corner and flipped it every time (next table), so
the low centre-flip counts and the ~0.85 m centroid offset (the half-diagonal is 0.87 m) follow from
the definition change. They are not failures of the old rule on its own terms.

### Every executed edit

| verb | n | total dV | dV in target | dV outside | median outside/total | outside/total of medians | target frac before -> after | centroid off | along n from centre | along n from hit | max shift | neighbours touched |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fill | 649 | 2.51 | 0.41 | 2.11 | 0.83 | 0.84 | 0.03 -> 0.52 | 0.39 | -0.31 | 0.19 | 1.09 | 18.00 |
| empty | 333 | 0.99 | 0.18 | 0.75 | 0.78 | 0.76 | 0.66 -> 0.47 | 0.23 | 0.13 | -0.08 | 0.35 | 13.00 |
| legacy_fill | 40 | 1.99 | 0.29 | 1.68 | 0.85 | 0.85 | 0.00 -> 0.29 | 0.83 | -0.28 | 0.42 | 1.30 | 9.50 |
| legacy_empty | 60 | 2.18 | 0.26 | 1.93 | 0.88 | 0.89 | 0.62 -> 0.32 | 0.87 | -0.44 | -0.49 | 1.30 | 13.00 |

| rule | executed | target centre flipped | target min corner flipped | edits flipping another centre | other centres flipped | max |centre pred - now| | max |neighbour pred - now| | neighbours whose predicted sign was wrong |
|---|---|---|---|---|---|---|---|---|
| current | 982 | 982 | 258 | 0 | 0 | 0.0000 | 0.0000 | 0 |
| legacy | 100 | 47 | 100 | 86 | 185 | 0.0000 | 0.0000 | 0 |

(Legacy predicted neighbours cover only the lattice its one-point write spans.)

The current rule's LP delivers what it promises: every executed edit flipped its target centre,
landed exactly on the predicted target and neighbour centre values (to the TSV's 4 places), and
flipped no other centre in the 5×5×5 around it.

| verb | executed | most-changed target solid frac after (fill: max, empty: min) | max dV in target | min dV outside | cube | bump/dent | invisible |
|---|---|---|---|---|---|---|---|
| empty | 333 | 0.13 | 0.84 | 0.03 | 0 | 332 | 1 |
| fill | 649 | 0.83 | 0.81 | 0.02 | 0 | 649 | 0 |
| legacy_empty | 60 | 0.00 | 0.48 | 0.68 | 0 | 60 | 0 |
| legacy_fill | 40 | 0.66 | 0.50 | 1.11 | 0 | 40 | 0 |

### Live vs dense, and what the diff box misses

- executed edits: 1082; live and dense total |dV| differ by > 0.001 m3 in 173 (max 0.18 m3); shape class differs in 0
- differing edits by class: cave_floor:3, cave_wall:4, gentle:17, near_zero_empty:3, near_zero_fill:3, ridge:50, slope:32, steep:59, valley:2
- live: edits moving vertices outside the +-2 cell diff box: 226 (max 13 vertices); edits with a window-capped column: 0
- dense: edits moving vertices outside the +-2 cell diff box: 136 (max 6 vertices); edits with a window-capped column: 0

Live and dense never disagree on shape. The diff box does not hold the whole change: a few vertices
outside it move (at most 13 in live, 6 in dense, against a median ~30 inside), so "dV outside" and
"neighbours touched" are lower bounds. I did not measure how far those vertices move.

### Occupancy measure against the field's sign

| terrain | phase | mode | regions | points | mismatch | points |sdf| >= 0.3 | mismatch there | worst region there | window-capped columns |
|---|---|---|---|---|---|---|---|---|---|
| hollow | after | dense | 61 | 953125 | 2.26 % | 746862 | 0.00 % | 0.03 % | 0 |
| hollow | after | live | 61 | 953125 | 2.26 % | 746862 | 0.00 % | 0.03 % | 0 |
| hollow | before | dense | 96 | 1500000 | 2.45 % | 1170330 | 0.00 % | 0.08 % | 0 |
| hollow | before | live | 96 | 1500000 | 2.45 % | 1170330 | 0.00 % | 0.08 % | 0 |
| open | after | dense | 123 | 1921875 | 0.62 % | 1697735 | 0.05 % | 0.99 % | 0 |
| open | after | live | 123 | 1921875 | 0.62 % | 1697735 | 0.05 % | 0.99 % | 0 |
| open | before | dense | 168 | 2625000 | 0.10 % | 2333311 | 0.01 % | 0.43 % | 0 |
| open | before | live | 168 | 2625000 | 0.10 % | 2333311 | 0.01 % | 0.43 % | 0 |

"Worst region" is the highest share of mismatching points in any one region. No column was
window-capped, so parity never inverted (an inversion would show as thousands of mismatches in one
region). Mismatch concentrates where |sdf| < 0.3: DC places the surface by QEF, not at the field's
zero, and on dug hollows mesh and zero set disagree on 2.3–2.5 % of points, all inside that band. The
figures above measure the rendered mesh, which is what the player sees.

### Click sequences (same eye and aim re-clicked; "adjacent" moves the eye and aim +1 m in x)

| scenario | step | n | refused (reason:n) | live shape | dV in target | dV outside | same cell as step 0 |
|---|---|---|---|---|---|---|---|
| adjacent_empty | 0 | 72 | already_air:33 | dent:39 | 0.29 | 1.00 | 72 |
| adjacent_empty | 1 | 72 | already_air:26 | dent:46 | 0.25 | 0.78 | 1 |
| adjacent_empty | 2 | 72 | already_air:31 | dent:41 | 0.23 | 0.92 | 0 |
| adjacent_fill | 0 | 72 | already_solid:5 | bump:67 | 0.46 | 1.81 | 72 |
| adjacent_fill | 1 | 72 | already_solid:1 | bump:71 | 0.39 | 1.75 | 0 |
| adjacent_fill | 2 | 72 | already_solid:2 | bump:70 | 0.34 | 2.00 | 0 |
| fill_then_empty | 0 | 120 | already_solid:7, lp_infeasible:12 | bump:101 | 0.46 | 2.03 | 120 |
| fill_then_empty | 1 | 120 | already_air:26 | dent:93, invisible:1 | 0.02 | 0.09 | 93 |
| repeat_empty | 0 | 72 | already_air:33 | dent:39 | 0.29 | 1.00 | 72 |
| repeat_empty | 1 | 72 | already_air:70 | dent:2 | 0.31 | 1.79 | 69 |
| repeat_empty | 2 | 72 | already_air:72 | - | - | - | 69 |
| repeat_fill | 0 | 120 | already_solid:7, lp_infeasible:12 | bump:101 | 0.46 | 2.03 | 120 |
| repeat_fill | 1 | 120 | already_solid:31, lp_infeasible:12 | bump:77 | 0.37 | 2.28 | 42 |
| repeat_fill | 2 | 72 | already_solid:22 | bump:50 | 0.38 | 2.63 | 12 |

Step 1 after a step 0 that executed (same cell as step 0?, outcome):

| scenario | step 0 executed | step 1 outcomes | step 1 same-cell executed: dV in target / outside |
|---|---|---|---|
| adjacent_empty | 39 | other cell already_air:8, other cell done:30, same cell already_air:1 | - / - |
| adjacent_fill | 67 | other cell already_solid:1, other cell done:66 | - / - |
| fill_then_empty | 101 | other cell already_air:18, other cell done:5, same cell done:78 | 0.02 / 0.08 |
| repeat_empty | 39 | other cell already_air:1, other cell done:2, same cell already_air:36 | - / - |
| repeat_fill | 101 | other cell already_solid:1, other cell done:77, same cell already_solid:23 | - / - |

### Material paint (fills, live mesh; "painted" = vertex carries the explicit Stone colour)

| verb | class | fills | new painted verts in target cell | new painted verts outside | moved verts | moved verts painted | fills with no painted vert in target |
|---|---|---|---|---|---|---|---|
| fill | cave_ceiling | 31 | 19 | 25 | 1170 | 44 | 12 |
| fill | cave_floor | 39 | 21 | 63 | 1312 | 84 | 18 |
| fill | cave_wall | 28 | 21 | 58 | 974 | 79 | 7 |
| fill | flat | 89 | 85 | 258 | 2359 | 343 | 4 |
| fill | gentle | 89 | 73 | 433 | 2608 | 502 | 16 |
| fill | near_zero_fill | 11 | 11 | 29 | 401 | 40 | 0 |
| fill | overhang_roof | 22 | 15 | 61 | 852 | 61 | 7 |
| fill | ridge | 90 | 75 | 566 | 2994 | 633 | 15 |
| fill | slope | 78 | 74 | 401 | 2834 | 471 | 4 |
| fill | steep | 79 | 70 | 273 | 2776 | 342 | 9 |
| fill | valley | 93 | 85 | 524 | 3119 | 607 | 8 |
| legacy_fill | flat | 6 | 6 | 0 | 96 | 6 | 0 |
| legacy_fill | gentle | 7 | 7 | 0 | 120 | 7 | 0 |
| legacy_fill | ridge | 8 | 6 | 1 | 128 | 6 | 2 |
| legacy_fill | slope | 5 | 3 | 0 | 92 | 3 | 2 |
| legacy_fill | steep | 6 | 4 | 1 | 107 | 5 | 2 |
| legacy_fill | valley | 8 | 5 | 0 | 146 | 5 | 3 |

- fill: 3206 of 21399 moved verts painted (15.0 %); new painted 549 in target vs 2691 outside (4.9x); 100 of 649 fills (15.4 %) put none in the target
- legacy_fill: 32 of 689 moved verts painted (4.6 %); new painted 31 in target vs 2 outside (0.1x); 9 of 40 fills (22.5 %) put none in the target

The dug caves carry no explicit material: `DigAction` keeps each leaf's existing material, and the
generator returns Bedrock only ~50 m down, so every painted vertex here is the fill's Stone.

### Hypotheses against the data

1. **Gameplay solidity and the rendered surface disagree: supported, strongly.** None of the 982
   current-rule edits reads as a cube. A fill takes the target from a median 3 % to 52 % solid; the
   best case was 83 %. The median change is 2.5 m³, of which 2.1 m³ (median share 83 %) lands outside
   the target. The change's centroid sits 0.39 m from the target centre, 0.31 m below it along the
   normal, and 0.19 m above the aimed hit: a mound on the original surface, centred just below the
   target cell. The surface moves by up to a median 1.1 m, over a median 18 or more neighbour cells
   (a lower bound), none of whose centres flipped. EmptyVoxel mirrors this with a ~1 m³ dent, 78 % of it outside the target, leaving
   the target ~47 % solid.

   Mechanism: the LP drives the target *centre* only 0.01 past zero, so the surface ends up passing
   through about the middle of the cell. Half-full is the design, not a malfunction. The pushes are
   large (median 0.99) and land on corners that 7 other cells share, so DC moves every vertex of the
   3×3×3 block, and the quads on those vertices move surface out to ±2 cells and a little beyond.

   Reasoning, not measured: at `RENDER_SUBDIV_LOG2 = 0` the render lattice *is* the gameplay lattice.
   A cube whose faces lie on the cell's faces would need sign changes exactly at lattice points, which
   DC on a 1 m lattice cannot draw. The smallest crisp feature it can draw is centred on a lattice
   point (a cell corner), which is what the old ±5 corner write made. A cell-aligned crisp cube looks
   to need a render lattice finer than the gameplay cell (LOG2 ≥ 1) or a different representation. I
   have not verified this against the mesher.
2. **Refusal where a cube was expected: refuted as stated, but refusal is real and common.** LP
   infeasibility is rare on open terrain: 0 of 4000 fills, 9 of 4000 empties (all on ridges), and 0
   of the near-zero-neighbour targets. It does show up in dug hollows: overhang roof fill 6/12, cave
   wall fill 3/12, cave ceiling 2/12. The dominant refusal is a different one. **EmptyVoxel refuses
   "already air" on 47.9 % of clicks** because it aims at the cell the surface passes through, and
   that cell's centre is air whenever the surface is below mid-cell. The old corner rule refused
   19.9 %. After a successful Empty, clicking the same spot again re-aimed the same cell and refused
   it 36 of 39 times; that cell is now centre-air but still ~half solid on screen. In practice
   EmptyVoxel cannot dig down.
3. **Material paint mismatch: supported.** 15 % of moved vertices carry the fill material (3206 of
   21 399). New Stone vertices appear 4.9× as often outside the target cell as inside it (2691 vs
   549), and 100 of 649 fills (15 %) put no Stone vertex in the target cell at all. The mesher paints
   a vertex from the leaf at `v − n·0.5`, and only the target leaf holds Stone. The result is a
   natural-coloured mound with a Stone patch that need not be centred on it. The legacy fill's paint
   stayed in its target: 31 new Stone vertices inside, 2 outside, across 40 fills.
4. **Expectation mismatch versus the old behaviour: supported that the change is large. Which part
   surprised Robert is unknown.** The old rule flipped its target corner every time and made a blob
   centred on that corner, 0.83 m (fill) / 0.87 m (empty) from the highlighted cell's centre. Seen
   against today's cell definition, it refused 39 % of fills and 20 % of empties and flipped other
   cells' centres in 86 of 100 edits. The new rule centres the change on the cell (0.39 m off),
   makes it bigger and smoother (2.5 m³ vs 2.0 m³, 18 vs 9.5 neighbours touched), fills almost
   always, and refuses empties more than twice as often.

### Also observed
- **Fill → Empty does not undo.** Of 101 successful Fills, the following Empty re-aimed the filled
  cell and executed in 78. It moves that centre from −0.01 to +0.01 and removes a median 0.02 m³
  in-cell plus 0.08 m³ outside, against the ~2.5 m³ the fill added. Gameplay then says air; the
  mound stays. Of the other 23, 18 aimed a neighbouring cell and refused as already air, and 5 aimed
  a neighbouring cell and dug an ordinary dent there.
- **Re-clicking Fill stacks.** After 101 successful Fills, a second Fill on the same spot re-aimed
  the same cell and refused it as already solid 23 times, refused a different cell once, and 77
  times filled a different cell, adding another bump of about the same size.
- FillVoxel fills the air cell *next to* the aimed surface (`hit + n*0.5`), not the cell the grid
  overlay highlights (`hit − n*0.01`). The overlay also aims with the physics ray against the
  collision mesh, while actions aim with `TerrainRaymarch`. I did not measure how often the two
  disagree.

### Questions for Robert
1. When you FillVoxel, what did you expect to see: a crisp 1 m cube aligned to the grid cell, or a
   smooth bump? Today you get a ~2.5 m³ smooth mound, about 83 % of it outside the target, with the
   target about half full. If a crisp cube is the goal, a render lattice finer than the gameplay
   cell, or another representation, looks necessary (see hypothesis 1).
2. Which cell should FillVoxel fill: the highlighted (surface) cell, or the air cell beside it,
   which is what it fills now?
3. In play, did EmptyVoxel mostly *refuse* (red ghost), or did it do something you didn't expect?
   It refuses 48 % of first clicks, and 36 of 39 second clicks on a spot it just emptied.
4. Should Empty right after Fill undo the Fill? Today it removes ~0.1 m³ of a ~2.5 m³ mound.
5. Should the paint cover the whole visible change, or only the target cell?

## Robert's answers (2026-09-27)
*Recorded by Claude from Robert's answer to the 2026-09-26 brief's question 1
([`overnight-2026-09-26.md`](../roadmap/implementation/done/overnight-2026-09-26.md), "Needs you
first"). Paraphrased; his words are in the brief.*

- **Expected:** crisp cube edits, while prepared for some curves, since the representation trades
  sharp corners for smooth landscapes.
- **Single-cell edits are not a game feature.** The player should be unaware of the grid: a board
  placed 10° off north should look about the same as one at 0° or 20°. Getting there will take
  tricks.
- **Their purpose is exact control of the SDF for testing**, which he suggested is better served by
  console commands: find a location with the probe, then set the values there. He asked what tools
  testing needs to expose and control the underlying data. That question is answered by
  [doc 22](../roadmap/design/22-scenario-languages.md)'s instrument layer: the probe reports the leaf,
  its field state, all 8 corners and the mesher's sign test, and console writes set a cell's 8
  corners, set a cell's material, or stamp a typed CSG shape by numbers. Doc 22 says these replace
  FillVoxel and EmptyVoxel as instruments.
- **What he expected a single-cell edit to do**, while unsure it's reasonable: the selected cell's
  corners end at SDF 0, its material changes to the current one if it differed, and its neighbours
  change little or not at all.

**Re-scope.** The question this file asked (what should a player's single-voxel edit look like) is
withdrawn: there will be no such player verb. What remains is making sure the instruments can
express Robert's expectation exactly, which "set a cell's 8 corners" + "set a cell's material" do.
Close this file when G4.4 lands. Whether FillVoxel and EmptyVoxel are then removed from the tool
belt or kept alongside is not decided here.

**One thing to know when trying it** (from the code, not measured): a cell whose 8 corners are all
0 has a sample value of exactly 0, and gameplay counts a cell solid only below
`SDF_SOLID_THRESHOLD` (0.0, `flip` in `engine/voxel_dc/edit_store_lattice.h`). So "corners at zero"
reads as **air** to gameplay. Which side of the surface the render puts such a cell on is what the
probe's sign test will show; I have not checked it.
