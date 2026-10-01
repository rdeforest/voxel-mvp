# docs/roadmap/reference — Index

Lookup material, not narrative. Each entry below notes *why the doc
exists*, not what it contains.

## Files

- [`01-answered-questions.md`](01-answered-questions.md) — the decision log
  that keeps resolved disputes from being relitigated.
- [`02-performance-budget.md`](02-performance-budget.md) — the frame-time
  budget table that holds systems to the 60fps target.
- [`03-folder-structure.md`](03-folder-structure.md) — the target project
  layout (aspirational; current state differs).
- [`04-asset-sources.md`](04-asset-sources.md) — the list of CC0 asset
  providers matching the project's licensing stance.
- [`05-elevator-pitch-long.md`](05-elevator-pitch-long.md) — the full
  Valheim-comparison pitch for when the short one needs backing.
- [`06-edit-and-movement-lifecycles.md`](06-edit-and-movement-lifecycles.md)
  — plain-language mental model of the edit and movement pipelines; the
  basis the incremental-LOD-splice design (doc 13) builds on.
- [`07-worldgen-research.md`](07-worldgen-research.md) — verified literature
  survey (2009–2024) on volumetric/stratified terrain and erosion simulation;
  the citations behind design doc 19, including the unsolved tileable-erosion
  crux.
- [`08-scenario-languages-research/`](08-scenario-languages-research/00_INDEX.md) — the
  prior-art research behind design doc 22: HTN languages, parametric assembly formats, field
  captures and Blender/VDB, and command-level record/replay.
- [`09-perceptual-lod-research.md`](09-perceptual-lod-research.md) — measured evidence (where the
  DC refine budget and triangles go, how wrong the mesh is at placed stones compared with a distant
  ridge, and why: scalar reconstruction versus exact Hermite data), a perceptual-LOD and
  shader-detail survey, and options for the "compelling, not accurate" design session. Research
  only; no decisions.
- [`10-godot-float-parsing.md`](10-godot-float-parsing.md) — why Godot's number reader
  (`String::to_float`, used by GDScript literals, `JSON.parse` and `str_to_var`) is not correctly
  rounded and reads tiny values as 0, the upstream state (issue #123700), and our options. The
  evidence behind [#13](https://github.com/rdeforest/voxel-mvp/issues/13) (`godot-float-parse-inexact`).
- [`11-voxel-farm-thin-features.md`](11-voxel-farm-thin-features.md) — how Voxel Farm (Miguel
  Cepero) handled features near two voxel sizes: he stated the Nyquist limit outright and worked
  around it (finer voxels, content aligned to the grid, textures at distance) rather than solving it.
  Background for reference note 09 and the "compelling, not accurate" session.
- [`12-known-contradictions.md`](12-known-contradictions.md) — where docs disagree with each
  other or with newer decisions, so a session asks instead of silently picking a side. Also
  lists open questions that must not be mistaken for decisions.
