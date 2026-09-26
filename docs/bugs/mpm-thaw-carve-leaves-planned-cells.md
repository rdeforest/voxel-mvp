# The MPM thaw carve leaves planned cells that touch kept terrain

*Filed by Claude (agent) on 2026-09-26, from the fix for mpm-thaw-events-unmeasured.*

**Status:** Open. Severity low: the detachment auto-trigger thaws a whole piece with air around it,
which clears completely; this bites the manual `mpmthaw` and any partial thaw.

## Symptom
Thaw a sphere of buried terrain and part of it stays in the ground. On the game's field
(`EditStoreManager.setup()`, centre `(0.5, surface - 3, 0.5)`), `thaw_sphere` plans the cells whose
centre is solid and empties fewer:

| radius | planned | emptied |
|--------|---------|---------|
| 3      | 63      | 52      |
| 5      | 176     | 143     |

A single buried cell (`thaw_cells([cell])`) empties nothing.

Until the events fix, every planned cell got 8 particles and a `voxel_removed` whether or not it
went air, so these cells were in the store and in the sim at once (duplicated matter). Now events
and particles follow the measured flips (`MpmStructure.thaw_cells`), so the thaw is honest about
what it moved; it just moves less than it was asked to.

## Cause
`MpmStructure._carve_corners` clears a lattice corner only if no kept-solid cell touches it, so the
wall stays clean. A planned cell next to kept terrain keeps those shared corners, and its centre is
the mean of its 8 corners, so with a few corners raised to `SDF_AIR` it usually still reads solid.
The whole outer shell of a thaw in solid ground is such cells.

## Separate effect seen while measuring
`StoreWrite.cells` rewrites its whole box (work plus a 1-cell margin, squared to a cube) from the
field's own corner samples. The generated field's value at a cell centre is not the trilerp of its
corners, so the rewrite alone flips some cells nobody edited: 17 air and 1 solid over 190 small
terrain thaws. The thaw now reports these (they are real changes to the store); whether the rewrite
should be allowed to make them at all is the same question every StoreWrite caller has
(`StoreWrite.one_cell` repairs it for single cells by LP).

These flips break conservation. An unplanned cell the rewrite empties becomes 8 particles, so
its matter shows up in the sim, possibly metres from the thaw: a radius-1.4 thaw emptied a cell
about 3 m outside the sphere. An unplanned cell the rewrite fills gets a `voxel_added` and matter
from nowhere, because nothing takes it out of the sim.

A thaw whose carve empties no cell leaves MPM idle, and DetachmentScout reads any edit made
while MPM is idle as a player's. `thaw_cells` sends no `TerrainSdfChanged` when its rewrite changed
nothing, so the scout re-floods such a piece at most once rather than every frame. Once the
carve can realize its plan, that case goes away.

## Proposed fix
Solve the carve like `StoreWrite.one_cell` does for one cell: pick corner values so every planned
cell's centre lands past zero toward air and every kept cell's stays solid, by a margin. Where no
such values exist, the plan is not carveable at 1 m and should be refused or reshaped, not silently
shrunk. Needs a decision on which (see the morning brief).
