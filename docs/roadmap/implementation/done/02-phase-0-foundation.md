# Phase 0: Foundation

**Goal:** Walking around a procedural voxel world with basic physics.
**Version target:** 0.0
**Status:** Complete. See `implementation-02-phase-0-foundation.md`.

## Tasks

- Set up Godot 4.6 project with godot_voxel (use pre-built binary or
  GDExtension).
- Configure VoxelTerrain node with VoxelGeneratorGraph or
  VoxelGeneratorScript.
- Basic noise-driven terrain (2–3 octaves of OpenSimplex).
- First-person character controller with gravity and collision against
  voxel mesh.
- Basic camera, movement, jumping.
- Day/night cycle (DirectionalLight3D rotation, simple sky shader).

## Key decisions

- **Meshing:** Start with VoxelMesherTransvoxel (smooth terrain). This
  is the "better than heightmap" visual argument.
- **Chunk size:** 16³ or 32³. Started with 16³ for faster iteration.
- **LOD levels:** godot_voxel handles this; 4–5 levels.

## Done when

You can walk across an infinite procedural landscape with hills, and
fall off cliffs.
