# SDF + noise stored/sampled as float — contradicts the double-precision planet-scale claim

**Status:** Deferred (2026-06-22). Diagnosed by code review. Negligible near the world origin; grows with
distance. Partly inherent (noise lib). At minimum, document as a known limit.

## Symptom (expected far from origin)
Terrain surface position and detail degrade with distance from the world origin, despite the engine being
compiled `precision=double` for planet-scale coordinates.

## Cause
Coordinates (`origin`, `size`) are correctly `double`, but two value paths quantize through `float`:

1. **Stored SDF corners are `float[8]`** (`engine/voxel_dc/edit_store.h:75`); `sample` trilerps them at
   float precision. For a value like `y - surface` with `y ≈ 10⁶`, float32 loses ~0.1 m near the surface.
2. **Noise sampled through float casts** (`engine/voxel_dc/terrain_field.h:62-63,78`):
   `noise.GetNoise(float(x), float(z))`. At `x ≈ 10⁶` the float cast quantizes the noise domain to ~0.06 m
   steps, so the surface is sampled on a coarse lattice far from origin. The `+1000.0f` bedrock offset is
   float too.

(2) is inherent to FastNoiseLite's float API — not fixable without a different noise source. (1) is fixable
(store `double` corners) at a memory cost.

## Proposed fix
Decide the acceptable roam radius and document the precision limit there, OR (if planet-scale edits far from
origin are in scope) store SDF corners as `double` and source noise from a double-domain generator. This is a
genuine hardware/precision trade-off, not a "good enough for now" — worth an explicit call per the manifesto.

## References
`engine/voxel_dc/edit_store.h` (`Node::corners`), `engine/voxel_dc/terrain_field.h`;
[[dc-sdf-not-unit-distance]].
