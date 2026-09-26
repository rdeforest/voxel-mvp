# FillVoxel / EmptyVoxel don't do what Robert expected in play (known unknown)

*Filed by Claude (agent) on 2026-09-25, from the agent review loop that fixed sdf-sample-corner-vs-center and actions-untyped-work-tuple.*

**Status:** Open, **known unknown**. Robert tried single-voxel edits in-game after `f11d284` and
`c9430a4` and "didn't get what I expected." Not yet characterized. It may be a misunderstanding of the
algorithm, an edge case, or both. The next step is to capture it: what was aimed at, what was expected,
and what appeared.

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
