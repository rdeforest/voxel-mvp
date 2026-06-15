# Phase 1: Biomes & Terrain Character

**Goal:** The world feels like it has places worth exploring.
**Version target:** 0.1
**Status:** Pending.

## Tasks

- **FEAT001**: Biome system — temperature/moisture noise maps → biome
  selection.
- **FEAT002**: Minimum 4 biomes — Meadow, Forest, Mountain, Swamp.
- **FEAT003**: Per-biome terrain parameters (amplitude, frequency,
  base height, cave density).
- **FEAT004**: Cave generation using 3D worm noise (continuous with
  surface — no loading screens).
- **FEAT005**: Water plane with basic shader (flat plane at sea level
  for MVP).
- **FEAT006**: Scatter system — trees, rocks, bushes as instanced
  MultiMeshes.
- **FEAT007**: Biome-appropriate vegetation distribution.

## Key decisions

- **Cave generation:** 3D Perlin worms or cellular automata carved into
  the voxel volume. Caves ARE the terrain. (Principle #2: no loading
  screens.)
- **Trees:** Scene instances on voxel surface, NOT voxel geometry. Use
  CC0 models.
- **Biome blending:** Smooth transitions via noise interpolation.

## Risk

Performance with thousands of scattered instances. Use godot_voxel's
instancing support.

## Done when

Walk from meadow through forest, climb mountain, find cave, walk in
(no loading screen), emerge elsewhere.
