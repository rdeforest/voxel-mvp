# World-Fixed Octree → Production Render (doc 16 Stage C)

**Status: DONE.** The world-fixed octree **IS the production render** (P1–P3 done, GPU-verified), and the
**code cleanup pass landed** — the retired parallel renders (the camera-centered clipmap `DCTerrainManager`,
the `dcgen`/SVO prototypes, the GDScript splice + `mesh_subregion`) are deleted. The only remaining items are
the **inside-coverage cracks** and the reversed-ridge triangles — deferred to the **bug bash**, tracked
one-file-each in [`docs/bugs/`](../../../bugs/00_INDEX.md). Successor to
[doc 16](16-persistent-octree-substrate.md) (which built + proved the substrate); this was its Stage C —
promote the octree to the render and retire the camera-centered clipmap.

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

### P1 — Surface-sparse prune over DIRECT sampling — DONE (2026-06-15)
**Landed.** `EditStoreSource` bakes a transient min/max accel grid over the resident window (octree-local,
one field sample per lattice unit — ~30× cheaper than the dense tree build) and `surface_free` runs the
clipmap's exact min/max test against it; `mesh_world`/`grow_world` enable the prune whenever a window is set.
Measured (0.25 m, depth 11): build **848→166 ms @ r=12 m**, **6610→749 ms @ r=24 m** (5–9×); grow +1 m
530→262 ms. Proven **surface- and order-preserving**: a whole-root windowed+pruned build is BYTE-IDENTICAL
to the dense build (`test_mesh_world_full_window_equals_no_window` now also asserts the prune fired). The
prune is conservative (checks actual samples) so it can't miss a crossing — never the Lipschitz over-prune.
*Remaining nit:* `grow_world` re-bakes the whole-window accel each move; bake only the band later.

*(original plan below)*

### ~~P1 — Surface-sparse prune over DIRECT sampling (the O(volume) wall)~~ (superseded by the above)
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

### P2 — Graded data floor for horizon coverage — MECHANISM DONE (2026-06-15)
The data floor coarsens with distance so a large window stays affordable. **One knob, `eps_px`** — the
floor DERIVES from it (`floor = eps_px·dist/proj`: build only as fine as a cell renders), and the prune
runs over a concentric world-anchored min/max accel (`EditStoreSource`, reusing `Clipmap::surface_free`)
so far empties are skipped at every distance. Validated by an `eps_px` sweep at 128 m / 0.25 m: 242 ms
(eps=128) → 27 s (eps=2) monotonically — the "fine everywhere" wall exists only at the fine end and is
**never chosen** because the budget controller settles `eps_px` where cost fits. There is **no separate
floor to tune** (an earlier divergence added one; corrected in `0b43068`).

**Budget controller (doc 13 B2) — WIRED + GPU-CONFIRMED (2026-06-15).** `DcWorldPreview` starts `eps_px`
coarse (48) and self-tunes against two costs: **frame time** (render) and **mesh lag** (worker WORK ms,
target ≤100 ms / ceiling ≤500 ms; not an FPS game). Coarsen if either is over, refine only when both have
headroom; backs off ×1.4, refines ×0.9. `dcworld` is now a 128 m coverage window, graded floor derived from
`eps_px`, full-rebuild on move. **In-game it settles ~`eps_px=94`** — works, terrain blooms coarse→detailed
then holds. `eps_px` is the only operating point (ACCEL_DIM, depth are API-shape).
- *Why it settles coarse-ish (~94, not finer):* the **accel-bake floor** — the concentric bake is a fixed
  mesh-lag cost independent of `eps_px`, so it eats lag budget the controller would otherwise spend on
  detail. Lowering it (incremental accel bake / serve `value()` from the baked grid) frees budget to refine.
  Not chased yet (Robert: meshing perf fine for now).

### P2.5 — Incremental band-diff (move latency) — DONE (2026-06-15)
A move now re-meshes only the band it touched, not the whole window. `reconcile` does the full incremental
band-diff: graft cells entering the window, evict those leaving, **refine cells the camera approached**
(graded floor now finer), **coarsen cells it receded from** — matching `build()`'s per-cell leaf/internal/
absent decision, so a `grow_world` against a new camera/eps yields a surface identical to a fresh build
there while re-sampling only the changed band. dcworld grows on a plain move or an eps change (the
controller re-grading); full rebuild only on first build / edit / re-root. Gate:
`test_grow_world_regrades_floor_on_camera_move` (grow-after-move == fresh build, samples << full).
**GPU-verify:** the bloom-on-walk is smooth and the controller settles across the cheap-grow / rare-rebuild
regimes.

### P3 — Make `dcworld` the live render — DONE (2026-06-15); cleanup pass landed (review pass 1)
`dcworld` is now THE terrain render: enabled at world startup, wearing the production terrain shader +
material palette. GPU-verified visually acceptable (Robert, 2026-06-15) — the inside-coverage cracks ride
along (tracked in `docs/bugs/`, deferred to the bug bash; Robert: "they're a feature now").
- **Cleanup pass — DONE.** The camera-centered clipmap (`DCTerrainManager`), the GDScript splice +
  `mesh_subregion`, `dcgen`/`DcSubstratePreview`, and the `SparseVoxelOctree`/GDScript-SVO prototypes are all
  deleted (commits `4e57cad` SVO/dcgen, `d58e8ce` clipmap). `mesh_clipmap`/`remesh` STAY — they turned out to
  be the load-bearing collision/falling-chunk/test-oracle mesher, not clipmap-render-only.
- Collision stays on the DC collision manager (its consolidation is separate).

## Known bugs (deferred → [`docs/bugs/`](../../../bugs/00_INDEX.md))

- **[dc-inside-coverage-cracks](../../../bugs/dc-inside-coverage-cracks.md)** — graded-floor coarse leaves
  place misaligned vertices → LOD-seam holes inside the coverage. Reproduced headlessly (6 @ eps=94);
  proactive accumulate-fine-QEF fix proposed. **Blocks P3** (retiring the clipmap needs a watertight render).
- **[dc-reversed-triangles-ridges](../../../bugs/dc-reversed-triangles-ridges.md)** — rare back-facing
  triangles on ridges; pre-existing, in the live render too.

## Future ideas (parked)

- **"Low-poly" material / geometry-source flag.** GPU-eyeing `dcworld` showed coarse (low-poly) terrain makes
  the watercolour line-art read *better*. So a per-material or per-geometry-source "low-poly" mark — render
  it deliberately coarse (a higher local `eps_px` floor, or a cap on subdivision) — could be an art lever,
  not just a perf fallback. Tangential to doc 17's substrate; capture for the art pass (doc 10 v0.2). (2026-06-15)
