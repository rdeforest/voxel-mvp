# Channel Architecture

The voxel grid is a multi-channel spatial database, not a single typed
value per cell. This chapter describes how channels compose and what
they're for.

The principle that motivates this lives in design principle #6: the
grid stores *what the matter is and what's happening in the volume*.
Roles and identities live in sidecar indexes.

## godot_voxel channels (current)

godot_voxel exposes voxel data as a multi-channel volume. Relevant
channels for this project:

- `CHANNEL_SDF` — signed distance field, float per voxel. Used by
  TransVoxel for smooth terrain. The "how far is this from the
  surface" mental model maps here.
- `CHANNEL_INDICES` + `CHANNEL_WEIGHTS` — texture blending for terrain
  (up to 4 materials per voxel, weighted)
- `CHANNEL_TYPE` — integer ID, used by the blocky mesher. Not relevant
  to this project's smooth-terrain approach.
- `CHANNEL_COLOR` plus several user channels — available for project-
  specific data

The voxel grid is a multi-channel spatial database. "What is this
voxel?" is not a single question; it's several independent questions
(SDF, material, temperature, moisture, ...) that share a coordinate
space.

## Channel resolution can vary per-channel

A non-obvious property: different channels can have different spatial
resolutions on the same conceptual grid.

- Temperature at 2m is fine because it diffuses slowly.
- Pressure for steam systems wants 0.25m or smaller.
- Wind vectors at 8m.
- SDF at whatever the terrain needs (mostly 0.3–1m, finer near build
  detail).

Each channel is sized for its physics. godot_voxel's channel system
already supports independent per-channel storage, compression, and
streaming. You're not paying for temperature data in empty sky.

## Future channels (v0.2+)

Channels are how non-rendered volume data lives in the world:

- **Temperature** — for thermal simulation, fire, comfort, weather.
- **Pressure** — for steam systems (the locomotive demo) and water
  dynamics.
- **Moisture** — for biome-driven generation, erosion, plant growth.
- **Wind vector field** — for atmospheric effects, sailing dynamics,
  smoke advection.
- **Smoke density** — participating-media volumetrics (rendered by
  ray-marching, not meshing; see DC-QEF chapter "Volumetrics" section).

The tree might be an iterated function system for its geometry, but
its temperature is tracked in the voxel grid at whatever resolution
thermal simulation wants.

## Roles live in sidecar indexes, not in voxel data

This is the load-bearing distinction. The voxel stores *what the
matter is*: SDF value, material ID, temperature, moisture, etc.
*Roles* — "this is part of player X's house, this is a load-bearing
wall, this is the door of the workshop" — are answered by sidecar
indexes maintained by their owning systems.

Example: when the player builds a house, the construction system adds
entries to its building-index dictionary keyed by voxel coordinate.
The voxels themselves don't know they're a house. If those voxels
later become rubble, the building-index forgets them; the voxels
don't need to change.

This is the same pattern as ECS: entities don't carry their roles, the
role-systems carry indexes of which entities they care about.

## After the DC-QEF transition

Under DC-QEF, the channels remain — they were always a property of the
data substrate, not the meshing method. What changes:

- The SDF channel becomes more meaningful (sampled at octree corners,
  contoured into arbitrary surfaces rather than blocky/Transvoxel
  meshes).
- Hermite data (point + normal at edge crossings) may live in an
  additional channel if storage allows, for crisp-feature DC.
- Volumetric channels (smoke, density) are unaffected — they were
  never meshed.

The channel architecture survives the meshing change unchanged. That's
the point of having it as a separate concept.
