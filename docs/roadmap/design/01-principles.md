# Design Principles

These aren't aesthetic preferences — they're the architectural thesis
that justifies choosing voxel over heightmap, and field-based voxel over
cube-based voxel.

The principles in the manifesto's "non-negotiables" section are the
operational version. This chapter is the longer-form rationale.

## 1. Terrain IS geometry

No distinction between "world" and "placed objects." A wall you build
and the cliff behind it are the same data structure. A house made of
dirt follows the same structural rules as a house made of wood.

The current shipped code has a remnant separation (separate part-support
and terrain-support algorithms, for good engineering reasons), but the
long-term direction is one field, one representation, one mesher. The
[DC-QEF geometry chapter](03-dc-qef-geometry.md) is the unification plan.

## 2. No loading screens

Caves, dungeons, and underground spaces exist in the same continuous
voxel volume as the surface. You walk in, you don't teleport.

This is the architectural argument against Enshrouded-style and Valheim-
style level transitions, and against Hytale-style world generation that
can't handle interior spaces.

## 3. Destruction and construction are real

Digging a hole removes voxels. Building a wall adds them. The engine
doesn't care whether terrain was generated or player-placed.

The Enshrouded compromise (modifications outside your base reset) is a
direct violation. The fix is not technical — it's a refusal to
compromise on this principle. A terabyte of SSD costs $150. Bandwidth
to sync chunk diffs is a solved problem. The whole point of voxels over
heightmaps is that modification is real.

## 4. Material physics matter

Dirt has an angle of repose. Stone can span gaps. Wood is strong but
burns. Every material in the world follows the same structural integrity
rules, whether it's terrain or construction.

The shipped structural integrity system implements the simplest version
of this principle (per-material decay rates). Future work extends it to
fracture mechanics (FEM-style stress tensors locally, see the
[known hard problems chapter](07-known-hard-problems.md)) and to
non-structural quantities (heat, pressure, fluid flow).

## 5. Moore's Law is a market dynamic

Don't over-optimize for 2025 hardware. Build the right architecture and
let hardware catch up.

The memory budget sanity check in the DC-QEF chapter shows why this
matters: a 100 km² world at 5mm detail is ~1.5 TB as a surface octree
— trivial on 2026 NVMe drives. Optimizing for the 8 GB RAM of a 2020
laptop would force architectural compromises that this project explicitly
rejects.

The performance budget table in
[`../reference/02-performance-budget.md`](../reference/02-performance-budget.md)
targets GTX 1660-class hardware — the floor of the Steam Hardware Survey
— but not below. Hardware below that floor is not the project's
problem.

## 6. The voxel grid is a spatial database, not just a renderable surface

SDF and material are channels in this database. Temperature, moisture,
pressure, momentum, and other 3D-continuous quantities can be additional
channels — possibly at different resolutions per channel. The grid stores
*what the matter is and what's happening in the volume*.

Roles, identities, and gameplay concepts (this is a building, this is
a load-bearing wall, this is a load-bearing wall belonging to player X's
house) live in sidecar indexes maintained by other systems, keyed by
voxel coordinate.

This is the principle that resolves the "what if a voxel is two types of
cell?" worry — it's a category error. The voxel stores what the *matter*
is. Whether that matter is *part of a building* or *part of a load-
bearing structure* is a role, not a property. Roles live elsewhere.

## 7. Terrain operations should fail honest, not fake a surface

When a terrain op can't cleanly do the intended thing, it should produce
truthful voxel data — even if that means opening a void — rather than
faking a result.

Example: a horizontal flatten that can't lower cleanly because there's
material above the cut should *open a small cave*, not invent a floor.

The whole argument for voxels over a heightmap is that the world is
honest geometry, not trickery. Valheim's flatten fakes things; ours
shouldn't. This is the principle behind Phase 5.5b (construction mode +
honest-failure terrain ops).

## How these principles compose

Together, the principles describe a world that is:

- **Honest** (#7): the voxel data tells the truth about what's there
- **Unified** (#1, #6): one representation governs everything
- **Continuous** (#2): no special transitions
- **Physical** (#4): material properties drive behavior
- **Persistent** (#3): everything you do remains
- **Future-aware** (#5): correctness now, performance from hardware later

When proposing a new feature, the test is: does the proposal satisfy all
seven principles? If it satisfies six and violates one, it's wrong. The
principles are non-negotiable in the manifesto's sense.
