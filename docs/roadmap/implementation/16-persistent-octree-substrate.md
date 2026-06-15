# Persistent Octree Substrate — staged plan (B3 / doc-10 completion)

*The B1-style stage plan for the one piece of [doc 10](../design/10-adaptive-octree-substrate.md)
that's still missing: making the render octree **persistent and world-fixed** so movement refines
it **incrementally** instead of triggering a full rebuild. This is "B3" from
[doc 13](../design/13-incremental-lod-splice.md). Each stage ships independently, stays tested, and
leaves the game working — the current clipmap keeps rendering until a stage is trusted.*

## Where we already are (the head start)

Doc 10's hard parts are **done**, which is why this plan is small:
- **Cells are world-aligned** (06-07 finding) — a cell of size S sits at a multiple of S.
- **Collapse is max-residual** — `DCOctreeMesher::accumulate()` uses the undivided QEF residual, so a
  spire vetoes its own collapse. (Doc-10 decision 1, confirmed: max-residual.)
- **The field is store-over-generator** — the render reads the `EditStore` + analytic `TerrainField`,
  not godot_voxel mips. (Doc-10 decision 2, settled.)
- **B1 splice** re-meshes a sub-box at the local LOD, crack-free, and the splicer is AABB-based.

**What's missing:** the render octree is **rebuilt and re-snapped every recenter** (root =
`round(player/16m)*16m`), so a move shifts the whole lattice frame → "everything changed" → full
rebuild. Fixing that is this plan.

## Confirmed decisions (doc-10 §"Decisions needed")
1. **Collapse metric:** max-residual — *done*.
2. **Fine-data sourcing:** settled (store-over-generator).
3. **Resident set / eviction:** **functional** — load aggressively, then evict anything whose absence
   wouldn't change what the user sees (out of view, or finer detail hidden behind a collapsed coarse
   cell). Optimistic load, prune-by-visibility.
4/5. **Storage / persistence:** reuse the `EditStore` model — node + 8 corners + material, with
   edited-node serialization. Not invented; already built.

## The stages

### Why the fold is mandatory (the splice-offset finding, instrumented)
Switching collapse to necessity (`we ≤ residual_tol`, camera dropped) is correct and proven
camera-independent — but it turns the **splice gate test red**, and the instrumented root cause is
the architectural lever for everything below:

- The splice meshes a **separate, smaller octree** rooted at `sub_origin` (offset from the full
  build's `root_origin`), then transplants its triangles. That offset frame is the whole problem.
- Instrumentation proved build floor (`level_index`/`target_cell_size`), collapse (`we`, byte-for-byte),
  and alignment (`align_cell`) are **all frame-identical** between the full build and the sub-octree.
  The divergence is purely in the **emit / point-location stitch at the sub-octree's artificial
  boundary** (30 vs 12 tris in the core box, 18 extra verts, 20 new boundary edges = cracks).
- The old screen-error metric's **slack** (hysteresis ×2.5 + the `/dist` scale) was silently absorbing
  this boundary divergence; the tight necessity threshold exposes it.

**The fix is structural, not a patch:** stop meshing a separate offset octree. Re-mesh the edited region
**within the same world-fixed octree as the full build**, so a splice's cells share the full build's
lattice *and its real neighbours* — no artificial boundary, no offset, crack-free by construction. That
is exactly the world-fixed substrate, which is why necessity-LOD and B3 are one fold, not two stages.

### Stage 1 — World-fixed grid + scrolling resident window
Replace "re-snap the root, rebuild everything" with "the cell grid is anchored to world coordinates;
a resident **window** of cells around the camera **scrolls**." When the player moves, build the cells
entering at the leading edge and evict those leaving at the trailing edge; the interior cells keep
their world positions **and their triangles**. This is the architectural heart — it turns a move from
"re-mesh the vicinity" into "re-mesh the edge band."
- **Files:** `dc_terrain_manager.gd` (the big rework — root is world-anchored, not player-snapped; the
  build becomes "build the window cells not yet meshed"; movement scrolls rather than re-snaps). The
  mesher likely gains a "mesh these specific world cells" entry beside `mesh_clipmap`.
- **Test:** walking re-meshes only a leading-edge band (verify with `dcinval` — green is a thin band,
  not the whole vicinity); the interior mesh is byte-identical before/after a small move.
- **First increment (the splice fix, derived from the finding):** make a splice **build on the full
  build's frame** (`root_origin` / `_ROOT_DEPTH`) instead of a separate `sub_origin` octree, with the
  build **pruned to the edit box + apron** (cells not overlapping it leaf-terminate before sampling, so
  cost stays proportional to the edit, not the whole root). Read only the box+apron sub-grid as today,
  but place it at full-frame coordinates so the meshed cells land on the *same lattice and neighbours*
  as the full build → the emit/stitch boundary is identical → crack-free, no `align_cell`, no
  `max_leaf` cap, no shared collapse-set. Mesher gains a `build_min`/`build_max` box; `_splice_job`
  passes the full frame + box. Rewrite the gate test to drive this (it currently mirrors the doomed
  offset path). This *is* the persistent octree's meshing op, minus persistence — Stage 1 proper then
  makes that octree survive across frames and scroll.
- **Then retire** the now-dead hysteresis (`prev/curr_collapse`, `HYST`, the `incremental` clearing/swap)
  and the vestigial `camera`/`proj` — all only existed to serve the old camera-driven collapse.
- **Risk:** this is where the design depth is. The LOD *levels* are world-anchored shells now (the
  geomorph `value()` is already a pure function of world position — confirmed — so no camera-orbit
  dependence); the resolution gradient stays (necessary at planet scale) but the frame is world-fixed.

### (former Stage 2 — Camera-driven incremental LOD — REMOVED by the LOD decision below.)
There is no camera-driven LOD to update: a cell's LOD is decided by **necessity** (a fixed world-space
residual tolerance), not by distance, so moving or turning the camera changes the displayed mesh by
**nothing**. The mesh updates only on (a) **edits** (B1, done) and (b) **window scroll** (Stage 1,
loading newly-resident cells). Telescopes fall out for free for the same reason: distant complex
terrain is already meshed fine because the detail is *necessary*, regardless of where you stand.

### Stage 2 — Eviction (the functional policy)
Bound the resident set: keep cells contributing to the displayed surface; evict out-of-view cells and
the finer nodes hidden behind a collapsed coarse cell. Load optimistically (window + margin).
- **Test:** memory bounded across a long traverse; a region evicted then revisited rebuilds identically.

### Stage 3 — Retire the full-rebuild + godot_voxel fallback
With 1–3 working, a full rebuild is only first-load / teleport. Drop the `dcmanager`/`dcsolo` fallback
to godot_voxel's render (doc-10's single-mesher consolidation). godot_voxel stays only as collision +
data store until its own retirement (doc 10 Phase B / doc 11).

## Sequencing & guards
- Stages 1→3 are ordered; each leaves the game shippable (the current clipmap path stays until Stage 1
  is trusted, behind the existing `dcmanager` toggle).
- The **crack-free gate** is the same as B1: an incrementally-updated mesh must equal a from-scratch
  rebuild over the same field. That equivalence test guards Stage 1 (the scroll/edge re-mesh).
- Validate on the real godot_voxel-encoded / store field, not analytic ([[dc-sdf-not-unit-distance]],
  [[validate-on-faithful-field]]).

## RESOLVED (the LOD decision): necessity, not distance
**A cell's LOD is decided entirely by necessity — distance from the camera is irrelevant.** A cell
collapses iff one vertex represents its surface within a **fixed world-space residual tolerance**
(the max-residual metric, *unscaled* — drop the `* proj / dist` screen term). Flat terrain collapses
everywhere; complex terrain stays fine everywhere; the camera is not an input.

Consequences (all simplifying):
- **The mesh is `f(field)`, not `f(field, camera)`** → camera motion triggers **zero** re-mesh.
  That deletes the whole camera-driven-LOD machinery (former Stage 2) and the re-snap-on-move problem.
- **No concentric LOD rings.** There are no levels keyed to camera distance; each cell is fine or
  coarse on its own surface complexity.
- **Telescopes are free** — distant detail is already resolved because it's necessary.
- **Cost moves to the budget.** Without distance coarsening, far complex terrain keeps its triangles,
  so **B2 tunes the world-residual tolerance** (coarser tolerance when over budget) — the one knob,
  now camera-independent. The resident-set radius (Stage 2 eviction) bounds the extent.

The C++ change is small: `accumulate()` already computes the residual `we`; collapse on
`we <= tolerance` instead of `we * proj / dist <= eps_px`. Camera params drop out of the mesher.
