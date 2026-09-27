# The detachment scout ignores MPM freezes, because seeding from them loops

*Filed by Claude (agent), overnight 2026-09-27 (Track F3), re-scoping the remaining part of
`mpm-freeze-flips-unmeasured` (whose other three parts are fixed).*

**Status:** Open. Severity low (a known hole in detachment, not a wrong world). The fix needs a
call from Robert.

## Symptom
The freeze's flips are measured now (doc 12, "The freeze (as built)"), but `DetachmentScout._on_edit`
still drops every `MPM` event. So a cell the freeze's 1 m rewrite empties never seeds a flood, and a
neighbour that lost its support through it isn't re-checked. The pile a freeze deposits isn't
checked for ground either.

## Why the seeding is off: it loops
Seeding from a freeze's flips (the solid neighbours of each air flip, and each solid flip, as
`_seed_collateral` does for the scout's own thaw) was built and measured with
`scripts/dev/probe_freeze_reflood.gd` (headless `test/support/scenario.gd` runs, game field):

| Case | Seeding off: freezes / scout thaws / rest frame | Seeding on |
|---|---|---|
| voxel dropped on a 1 m grid post | 1 / 1 / 127 | **8 / 8 / 578** |
| 14 other cases (fence beam; voxel, r1.5 ball, r3 thaw at 4 spots; 16 voxels on slopes) | 1 thaw per fall | same thaws; extra floods all grounded, rest up to 28 frames later |

The post is `CsgBoxShape(1, 12, 1)` centred on a cell column (`x, z = 100.5`). Every lattice corner of
its cells lies on its faces, so each cell centre samples SDF 0.00, and solid means `sdf < 0`: to
`GroundFlood` the post is air. The particle collider still holds material on it. So the voxel lands on
the post and freezes, the scout floods the pile, finds it DETACHED, thaws it; it lands one cell lower
and freezes again. Each cycle turns one post cell into pile. It stops only at real terrain (8 cycles
for this post; a longer post loops longer). GUT pins the seeding-off behaviour:
`test_detachment_scout.gd`, `test_a_pile_frozen_on_a_post_the_flood_cannot_see_is_not_thawed_again`.

Other contact shapes the seeding was run on did not loop: slab edge and corner, a 45° rotated slab, and
slopes (every frozen pile shared at least 3 faces with solid ground). Diagonal-only contact, suspected
earlier, was not reproduced; the loop found is "resting on geometry the flood reads as air".

## Mechanism
Two definitions of solid disagree: `TerrainProbe.is_solid` (cell centre, `sdf < 0`) and the MPM
collider (the store's field, which holds particles on an SDF-0 surface). Any geometry thinner than
the lattice can resolve, or aligned so its cell centres read exactly 0, is air to the flood and ground
to the particles. Seeding from freezes turns that disagreement into a thaw/freeze cycle.

## Fix options (Robert's call)
1. **Make the two agree.** Decide what "solid" means for sub-resolution geometry at one place and use
   it in both the flood and the collider. The deeper fix; it changes `TerrainProbe.is_solid` (or the
   collider), which everything structural reads.
2. **Break the loop in the scout.** Don't thaw a DETACHED component made only of cells the freeze
   just made solid. Cheap, but it makes the pile's "detached" verdict a special case.
3. **Keep ignoring freezes** (current). The hole stays: a cell a freeze empties never re-checks its
   neighbours.
