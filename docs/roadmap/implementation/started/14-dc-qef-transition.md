# DC-QEF Transition

*The one-shot migration plan. The permanent spec is at
[`../../design/03-dc-qef-geometry.md`](../../design/03-dc-qef-geometry.md).
When this work lands, this chapter becomes history — kept around as
record of how the transition was done, not as ongoing reference.*

## Motivation (the short version)

The current shipped code uses godot_voxel's TransVoxel mesher. That
mesher takes the SDF channel and produces smoothed terrain — fine for
the v0.0 thesis, but it embeds the cube model that the
[principles](../../design/01-principles.md) and the
[manifesto](../../../MANIFESTO.md) reject.

The deferred items that should have shipped in v0.0 — sub-cell parts,
true voxel-wall-blending-into-rock geometry, fracture along arbitrary
surfaces rather than voxel-aligned cubes — are all symptoms of the
same root cause: TransVoxel can produce smooth surfaces, but it can't
produce *off-grid* surfaces. The vertex placement is constrained.

DC-QEF removes that constraint. The vertex sits anywhere inside the
cell — including precisely on a crease. Sharp architecture and smooth
terrain become one mesher.

This transition is *the* simplification: it collapses the part/terrain
dichotomy into one representation. It is also *not* a Hytale-style
rewrite. godot_voxel's storage, streaming, and LOD stay; only the
meshing layer (~15–20% of what godot_voxel does for us) is replaced.

## When to do this

Most likely landing point: v0.2. The reasons:

1. v0.1 has gameplay work that can ship on TransVoxel.
2. The DC-QEF transition's biggest cost is the LOD seam handling
   work, which is best done when we have a stable v0.1 to validate
   against.
3. v0.2 is the art pass — the moment when "smooth + sharp on the same
   mesh" becomes user-visible benefit.

The transition could theoretically happen earlier or later. The
constraint is that it should happen *before* anything that depends on
crisp features in the geometry (locomotives in v0.9 are an absolute
deadline; sub-meter fracture in v0.1 5.5c is a soft deadline since
the fracture can still extract from a TransVoxel mesh).

## What godot_voxel layers we keep

godot_voxel is a stack, not just a mesher. We replace one layer:

1. **Storage** — `VoxelData`, sparse blocks, the modification/SDF-edit
   API. **Keep.**
2. **Streaming** — `VoxelStream` (disk), `VoxelGenerator` (procedural),
   bg threads. **Keep.**
3. **LOD** — octree LOD, distance-based clipmap, transition/seam
   handling. **Keep the octree; replace the seam handling.**
4. **Meshing** — `VoxelMesher` (Transvoxel / Blocky) on worker threads
   → `ArrayMesh`. **Replace.**
5. **Engine glue** — `VoxelTerrain`/`VoxelLodTerrain` nodes, collision
   shapes, thread pool, material/shader hookup. **Keep.**

The clean migration path: keep godot_voxel storage + streaming + LOD
octree, subclass `VoxelMesher` as `VoxelMesherDualContouring`, replace
only item 4.

## The real costs

godot_voxel does three things *around* the mesher that we have to
re-implement or work around:

1. **LOD seams become ours, and DC makes them worse.** Transvoxel
   exists *specifically* to stitch LOD cracks; naive DC across an
   octree LOD boundary cracks. Needs octree-DC with restricted-balance
   + matching subdivision on shared edges, or Manifold DC. **This is
   the real work — budget more here than for the base mesher.**
2. **Collision.** godot_voxel auto-generates collision from meshed
   chunks. Our DC triangle soup → `ConcavePolygonShape3D` per chunk,
   regenerated on edit.
3. **Threading + edit→remesh pipeline.** Re-implement dirty-chunk
   queue → bg remesh → main-thread swap. (We already have a bus +
   dirty-queue discipline from Phase 5.5a — reuse that shape.)

The catch: godot_voxel stores SDF as a single scalar per voxel; true
sharp-DC wants **Hermite data** (point+normal at crossings). Scalar-
only + finite-diff gradients gives *smooth* DC but loses guaranteed-
crisp creases. Crisp features → extend storage (Bite E below), which
is also the seam where "borrow godot_voxel" ends and "own the stack"
begins — and where the decentralized op-log storage plans (see
[network architecture](../../design/05-network-architecture.md)) will
eventually replace `VoxelStream` anyway.

Whether existing code is untouched: if it talks to the **edit API** +
reads meshes/collision, yes. If it touches `VoxelLodTerrain`/
`VoxelStream`/LOD APIs directly, those leak.

## Granular, scope-isolated bites

Each can be picked up cold without holding the rest in your head.

- [ ] **Bite A — Plain DC mesher, smooth only.** Scalar field in,
  triangles out. Sign-change detection, finite-difference normals, QEF
  (SVD + clamps), quad emission. No Hermite, no LOD. Success = a
  smooth sphere/blob meshes correctly from an analytic SDF.
- [ ] **Bite B — QEF robustness harness.** Unit tests for the ill-
  conditioned flat-region case; confirm vertices stay in-cell. Isolated
  from everything.
- [ ] **Bite C — Sharp-feature test.** Mesh an analytic box/wedge;
  confirm the QEF recovers 90° edges. Depends on A.
- [ ] **Bite D — Octree DC + seam handling.** The real work.
  Restricted/balanced octree, shared-edge contouring rule, transition
  matching. Depends on A.
- [ ] **Bite E — Hermite storage extension.** Only if/when crisp
  creases are needed; store point+normal at crossings. May force off
  godot_voxel storage. The **crease-aware normal splitting** half (hard-edge
  *shading*) is **done in the prototype**: `MeshNormals` regroups each vertex's
  faces by angle — smooth where the surface is smooth, split the shared vertex
  at a crease — fixing DC's one-averaged-normal-per-cell soft bevel. What
  remains for Bite E is the *storage* half: godot_voxel stores scalar SDF only,
  so the engine path must store or recompute point+normal at crossings to feed
  those crisp normals. Lands with F.
- [ ] **Bite F — godot_voxel `VoxelMesher` subclass.** Slot A into
  godot_voxel's existing storage/streaming/LOD/collision/threading.
  **Decision (2026-06-03):** our C++ lives in a *separate module* (not
  edits to the pinned godot_voxel clone, which `tools/build` checks out
  detached and refuses-on-dirty). `tools/build` gets extended to symlink/
  build the extra module; its stamp must also track the module's source so
  local C++ edits trigger a rebuild (today it hashes only the pinned refs +
  args). Day-to-day F iteration uses `scons` directly (incremental relink);
  `tools/build` stays the sync-to-pins ritual.

## Bite F2 — LOD seam transitions (in progress)

> **SUPERSEDED (2026-06-05):** the per-block `transition_surfaces` / wide-padding
> band plan described in this section was abandoned — real terrain boundary loops
> span multiple cube faces, which godot_voxel's per-side transition model can't
> carve up. We pivoted to building **our own meshing/render layer** over
> godot_voxel's data (path b). Current direction + progress live in
> `docs/STATUS.md` ("Active thread"). The material below is kept as the record
> of how we got there (the `dc_seam` loop extraction + zipper it produced are
> still reusable).

**Status (2026-06-03):** F1 (real C++ DC) shipped. Same-LOD seams are
crack-free (boundary padding makes adjacent same-LOD blocks compute identical
boundary vertices). Generated-terrain **see-through holes are fixed** — they
were back-facing triangles, not topology: sign-based winding + shorter-diagonal
split + in-cell QEF fallback (committed; regression tests in
`test/test_dual_contour.gd`). The remaining open item is **LOD-boundary cracks**.

**API finding:** the per-block API *does* support transitions. `VoxelMesher`
`Output` has `transition_surfaces[6]` (one per cube face) and the terrain
computes a per-block `transition_mask` at runtime (`get_transition_mask` in
`voxel_lod_terrain_update_task.cpp`) marking faces that border a *coarser*
neighbour, then shows the matching transition surface. So the fix is additive:
fill `transition_surfaces[face]`; the main mesh stays full-res (still correct
for same-LOD neighbours), and the band is shown only when that face is coarse-
bordering. (This is the Transvoxel render model; *seam-octrees* à la Gildea were
the thing that didn't fit — they need neighbour-block access.)

**Why it's hard for DC:** DC vertices are off-grid QEF points in cell interiors,
not on shared edges, so a fine block and a coarse block of the same field place
*different* boundary vertices — they don't align across resolutions (Transvoxel
sidesteps this because its vertices are on edges, shared by construction).

**Planned approach — additive transition band (the higher-res block builds it):**
On a face bordering a coarser neighbour, the fine block emits a band that stitches
its **full-res seam contour** to the **coarse seam contour**. The fine block can
reproduce the coarse contour exactly by sampling the field at 2× spacing and
running the same QEF — so the band's coarse side equals the coarse block's actual
boundary vertices → watertight after welding. Steps: (1) extract the fine mesh's
open boundary edges on the face as ordered loop(s); (2) recompute the coarse
boundary cells' vertices; (3) zipper the two loops into a triangle band → into
`transition_surfaces[face]`.

**Band algorithm — DONE (GDScript prototype).** `scripts/dc/dc_seam.gd`:
`open_loops()` extracts a mesh's oriented open-boundary loops; `stitch()` zippers a
fine loop to a coarse loop into an additive band (winding-matched, nearest-start).
`test/test_dc_transition.gd` proves it: a fine block + coarse block of one sphere
goes from **64 boundary edges to 0** when the band is welded in. This is the
geometry that goes into the engine's `transition_surfaces[face]`.

**Padding decision (2026-06-04): wide padding ("make it work").** The fine block
will recompute the coarse loop by sampling the field at 2× spacing past the face,
which needs `MIN/MAX` ≈ `5/5` (up from `2/3`) — so every block's buffer ~doubles
and meshing is up to ~2× slower (on worker threads), even for the majority of
blocks not at a LOD boundary. Accepted as the simplest correct port of the proven
prototype; if the cost bites, optimize later to a **seam pass** (a post-mesh pass
with neighbour access — exact and pays only at seams, but a restructure against the
per-block API). Approximate (decimate-own-loop) was rejected — leaves hairline
cracks.

**C++ port plan (not yet started — integration-heavy, only verifiable in-game):**
1. Bump `set_padding` to ~5/5; confirm same-LOD seams + the hole fix still hold.
2. Port `open_loops` / `stitch` to the C++ mesher.
3. For each of the 6 faces: extract the main mesh's open loop on that face;
   recompute the coarse loop by meshing the coarse cells just past the face (2×
   spacing, from the widened padding); zipper → `Output.transition_surfaces[face]`.
   Build all faces unconditionally — godot_voxel shows them per `transition_mask`.
4. Verify in-game with `vdebug active_mesh_blocks` at a real LOD boundary; watch
   meshing time for the padding cost.

## When this lands

- Mechanism rationale graduates into `../../design/architecture.md`.
- Decisions added to
  [`../../design/02-architectural-commitments.md`](../../design/02-architectural-commitments.md).
- This chapter becomes a historical record (not deleted — the
  reasoning about WHY the transition was done remains valuable for
  future-you and future-Claude).
