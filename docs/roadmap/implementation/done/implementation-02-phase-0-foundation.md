# Completed: Phase 0 — Foundation

Maps to [`02-phase-0-foundation.md`](02-phase-0-foundation.md).

## What shipped

Procedural terrain, FPS controller, gravity, day/night cycle.

- Godot 4.6 stable + godot_voxel double-precision build pinned in
  `tools/versions.env`.
- `VoxelLodTerrain` configured with a noise generator.
- First-person `CharacterBody3D` controller with mouse look, WASD
  movement, jump, gravity.
- Crosshair-equipped HUD.
- Day/night cycle via DirectionalLight3D rotation.

## Key decisions taken

- Track Godot 4.6 stable, not master. (Reasoning preserved at
  [`../../reference/01-answered-questions.md`](../../reference/01-answered-questions.md).)
- Use the double-precision godot_voxel build from day one.
  Non-retrofittable.
- TransVoxel mesher for smooth terrain (will be replaced by DC-QEF in
  v0.2; see
  [`../started/14-dc-qef-transition.md`](../started/14-dc-qef-transition.md)).

## Validation

Walking across an infinite procedural landscape with hills, falling
off cliffs. Done.
