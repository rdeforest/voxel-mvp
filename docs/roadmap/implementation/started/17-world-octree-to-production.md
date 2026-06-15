# World-Fixed Octree → Production Render (doc 16 Stage C)

**Status:** Active. The successor to [doc 16](../done/16-persistent-octree-substrate.md), which BUILT and
PROVED the world-fixed incremental octree (`mesh_world` + `grow_world`, headless-gated) and wired it to a
live PREVIEW (`dcworld`). This doc is the remaining work to make it the **production render** and retire the
camera-centered clipmap — doc 16's Stage C, split out so 16 could close on its achieved deliverable.

**Read first:** doc 16 (the substrate + why), `docs/MANIFESTO.md` (one field / one representation / the grid
is a world-fixed spatial database / no half-measures), and the `dcworld` triage notes in `docs/STATUS.md`.

## Where we are (the head start from doc 16)

- **The world-fixed incremental octree exists and is proven headless:** `mesh_world(... win_min, win_max)`
  (windowed build, absent rim), `grow_world` (graft leading edge / evict trailing / reuse interior,
  byte-identical to a fresh build, samples only the new band), free-list-bounded resident set. Tests in
  `test/test_dc_world_octree.gd`.
- **It's visible:** `DcWorldPreview` (`scripts/dc/dc_world_preview.gd`) renders it at production density
  (0.25 m) as an amber overlay; `dcworld [on|off] [radius]`. Re-root = `mesh_world`, move = `grow_world`,
  edit = rebuild; threaded.
- **The one thing blocking a full render is coverage:** the build is DENSE to the floor, so 0.25 m is
  O(volume) → only a small bubble is affordable. Everything below is about removing that wall, then
  flipping the switch.

## Stages

### P1 — Surface-sparse prune over DIRECT sampling (the O(volume) wall)
The clipmap's exact min/max prune (`Level::build_mip` / `surface_free`) works because the clipmap has a
**pre-baked grid to mip against**. `EditStoreSource` samples the analytic field directly — **there is no
grid** — so `EditStoreSource::surface_free` abstains and the build descends every cell to the floor.
- **The hard part / the trap:** the deleted gradient-estimate (Lipschitz) prune OVER-PRUNED and broke
  watertightness ([[dc-sdf-not-unit-distance]], the doc-16 cautionary tale). A magnitude/interval bound on
  this non-true-distance SDF is exactly that trap. Do NOT repeat it.
- **The candidate that can't miss a crossing:** bake a coarse **min/max acceleration grid** on demand by
  sampling the field at a stride, then prune via the exact min/max test (same guarantee as the clipmap's
  mip — it checks actual samples, so it physically can't skip a sub-cell ridge). Cost moves from
  "descend every cell" to "sample a coarse grid + descend only surface cells." Gate: pruned+collapse
  surface == dense+collapse surface, watertight WITH collapse, on real terrain.

### P2 — Graded data floor for horizon coverage
Even surface-sparse, a 0.25 m floor over a 1 km horizon is too many cells. Coverage to view distance needs
the data floor to **coarsen with distance** (fine near, coarse far) — the world-fixed analogue of the
clipmap's LOD levels, but driven by detail/distance in the data source, not a camera-snapped grid.
`EditStoreSource::target_cell_size(p)` returns the floor; make it grade. Gate: coverage reaches view
distance at a bounded cell count; near detail unchanged.

### P3 — Make `dcworld` the live render; retire the clipmap
With P1+P2, the world-fixed octree covers the view at an affordable cost. Promote it: a `dcworld` manager
modeled on `DCTerrainManager`/`DcSubstratePreview` becomes the default render, and the camera-centered
clipmap levels + geomorph blend + the `dcgen`/SVO render are retired (least-duplication — delete a parallel
mesher, don't copy). Collision stays on `VoxelMesherDC` until its own consolidation.
- Gate each step: watertight-WITH-collapse + full GUT green + `dcinval` shows a thin re-meshed band on a
  move (not the whole vicinity) + **GPU eyes** on the live terrain (render correctness can't be trusted
  headless).

## Known limit to fix along the way

- **Reversed triangles on ridges (shared meshing/winding code).** A quad straddling a convex ridge is
  non-planar, but `emit_poly` orients both its triangles to ONE shared `outward` (the edge-crossing
  gradient), so the triangle whose true facing opposes it comes out back-facing. **Pre-existing — present
  in the LIVE clipmap render too** (24 reversed vs `mesh_world`'s 18 across 81 sample 64³ regions), so it's
  not a world-octree bug. Rare (~1 per few thousand triangles). **Fix hypothesis:** give each triangle its
  OWN outward — the mean of its three vertices' QEF normals (free, already computed) or the field gradient
  at its centroid (independent). Touches the live render → needs GPU eyes. Logged, deferred (2026-06-15).
