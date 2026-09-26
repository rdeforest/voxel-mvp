# MpmStructure.thaw emits voxel_removed from its plan, not from measured flips

*Filed by Claude (agent) on 2026-09-25, from the agent review loop that fixed sdf-sample-corner-vs-center and actions-untyped-work-tuple.*

**Status:** Open. Severity low. Every action now measures its events across the write; the MPM thaw
path is the one that still doesn't.

## Cause
`scripts/structural/mpm_structure.gd:91` emits `voxel_removed` for each thawed cell before or
alongside its corner write. It decides which cells to thaw by the centre sample
(`TerrainProbe.is_solid`). Carving shared corners can flip neighbours too, and those neighbours are
never reported. This is the kind of mismatch between events and write that the actions no longer
have.

## Proposed fix
Sample before and after the carve over the rewritten box and emit the measured `CellFlips`, as
`VoxelImprint.apply` does.
