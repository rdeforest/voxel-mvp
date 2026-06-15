# Phase 2: Terrain Modification

**Goal:** Dig, flatten, raise terrain with tools.
**Version target:** 0.0
**Status:** Complete. See `implementation-03-phase-2-terrain-modification.md`.

## Why this came before biomes

For the v0.0 validation ("is this as good an idea as I think it is?"),
you need to feel terrain modification before you need pretty biomes.
Can you dig a cave? Does it feel right? That question matters more
than whether the meadow transitions nicely to the forest.

## Tasks

- Voxel editing API: sphere/box brush that modifies VoxelBuffer SDF
  values.
- Dig (reduce SDF), fill (increase SDF), flatten (set to plane).
- Visual feedback: crosshair raycast showing edit preview.
- Tool system foundation: equip tool → determines edit mode and
  parameters.
- Terrain modification persistence (godot_voxel built-in chunk save/
  load).
- Particle effects on terrain edit (dust, debris). [Deferred to v0.2.]
- Vertical flattening prototype: create a sheer face in rock (SDF
  operation that sets a vertical plane).

## Key decisions

- **SDF editing** gives smooth, natural terrain modification — a huge
  visual win over Valheim's crude flatten/raise.
- **Vertical flattening** is an SDF plane intersection operation. For
  the prototype, instant. The "takes time based on material and skill"
  mechanic is a gameplay layer added later (v0.1, via continuous work
  actions).

## Done when

You can dig a tunnel into a hillside, carve out a room, build a mound,
and cut a sheer vertical face in a rock wall.
