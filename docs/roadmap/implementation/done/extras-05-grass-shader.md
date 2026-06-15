# Completed: Grass Shader

**Commit:** `eedef27`

## What shipped

The terrain surface no longer looks like flat green paint. Slope-based
grass/dirt blending with a wind-animated grass surface.

- **Slope-based grass/dirt blend.** Shallow slopes show grass; steep
  slopes show dirt. Smooth transition via slope thresholding.
- **4-octave gradient-noise wind animation** on the grass surface.
- Uniforms tweakable via Godot's editor Remote inspector or the
  Limbo Console `set` command.

## Key decisions taken

- **Slope as the primary blending factor.** Not altitude, not biome —
  *slope*. Grass grows where it can take root; that's a slope question
  more than anything else. This will compose well with biome work in
  Phase 1 (biome controls *which* slope-aware materials are used).
- **Gradient noise, not value noise.** Gradient noise produces
  smoother, more natural-looking wind patterns at the spatial
  frequencies that read as "wind" rather than "static."
- **Animate on the surface, not the geometry.** This is shader work
  in the fragment stage, not vertex displacement. Cheap; doesn't
  affect collision; doesn't interact with structural integrity.

## Lessons learned

- **This is a placeholder, and it's *good enough as a placeholder*.**
  The v0.2 art pass will produce a proper terrain shader with
  triplanar texturing, moss/snow accumulation, biome variation. This
  shader exists so the v0.0 thesis demo and the v0.1 work-in-progress
  builds don't look quite as much like flat-shaded prototypes.
- **Tunable uniforms via Limbo Console pays off.** Being able to
  `set grass_wind_strength 0.3` at runtime is fast iteration without
  rebuilding shaders. Pattern worth repeating for other visual
  tuning.

## Deferred

- **Triplanar texturing** — v0.2 art pass. → FEAT053.
- **Snow / moss accumulation** — v0.2 art pass.
- **Vertex displacement for tall grass / actual grass blades** — much
  later; would interact with the meshing pipeline.
- **Per-biome grass color** — wait for biome system. → Phase 1.
