# Incremental LOD Splice (edits + camera at any distance, no full rebuilds)

*The design spec for making terrain edits patch the displayed mesh incrementally at
**any distance and any LOD**, instead of falling back to a full clipmap rebuild. Builds
on the DC render layer ([`10-adaptive-octree-substrate.md`](10-adaptive-octree-substrate.md))
and the edit storage ([`11-octree-edit-store.md`](11-octree-edit-store.md)). Motivated by a
concrete symptom — at sub-metre, **every** edit triggered a full re-mesh — and a design
principle: the only legitimate limit is the hardware, so detail should be sized to a
runtime budget, not a constant.*

## TL;DR

Today an edit tries an incremental **splice** (re-mesh a small box on a worker, swap its
triangles into the cached mesh by AABB) but **only within a fixed ±11.5 m "fine core" and
only at the finest LOD**. At sub-metre that core shrank 4× (it was ±~46 m at 1 m) and is
now smaller than both the 16 m LOD-snap wobble and the 30 m edit reach, so nearly every
edit lands outside it and falls back to a **full rebuild of all 7 LOD levels** — hundreds
of ms of O(volume) work to move a handful of cells.

The fix (**B1**) is to let the splice mesh at the **local LOD** the displayed mesh already
uses there, so any edit at any distance patches a spatial box at the right resolution.
**B2** then makes the detail budget (`eps_px`) a runtime controller instead of a constant,
which dissolves the "fine core" entirely — resolution everywhere becomes emergent and
self-tuning to the hardware. **B3** (deferred) extends the same machinery to camera motion,
retiring full rebuilds altogether.

## Why the boundaries aren't special (the load-bearing insight)

A natural worry about octrees: an edit straddling a high-level branch boundary ("half the
world") might cascade work up the tree. **It doesn't, and can't, here** — for two reasons:

1. **The splice is spatial, not topological.** The cached mesh is a triangle soup plus one
   *owner-cell origin per triangle*. A splice ([`dc_edit_splicer.gd`](../../../scripts/dc/dc_edit_splicer.gd))
   drops cached triangles whose owner-cell is in an AABB `[core_min, core_max)`, appends the
   patch's, and compacts. It never walks to the root, never rebalances. An edit on the root
   split plane patches the same box as one anywhere else. (The render octree is also
   *player-centred* and re-snaps each rebuild, so there is no fixed world boundary at all;
   the storage octree ([`11`](11-octree-edit-store.md)) is world-anchored but its empty
   octants simply don't exist as nodes.)

2. **A cell's LOD decision is subtree-local.** In `DCOctreeMesher::accumulate()` a cell
   collapses to one vertex iff its *accumulated QEF residual* (its own subtree's Hermite
   data) clears the screen-error threshold `eps_px` at its camera distance, with hysteresis.
   This depends on **the cell's own subtree + camera + eps_px + the hysteresis set — never on
   neighbours outside it.** So a patch that reproduces those three inputs reproduces the
   decision exactly.

Together these give the crack-free guarantee in generalised form (see next section), and
they mean **cost is ∝ edit-box volume × local resolution, independent of world position** —
the invariant we want: *an event on both sides of any boundary costs the same as anywhere.*

## The crack-free invariant, generalised

Today's splicer docstring states the current guarantee plainly: *"the uniform 1 m fine core
guarantees the patch's per-cell vertices match the full build's, so the boundary between
kept and patched triangles is seam-coincident."* B1 generalises **"uniform 1 m"** to
**"the patch reproduces the cached mesh's exact LOD + collapse at its boundary."**

By the subtree-locality above, a patch is crack-free iff, for every cell whose triangles it
emits, it:

- **(a)** snaps its box to whole cells at the local coarsest LOD it touches,
- **(b)** contains that cell's **full subtree** (so its accumulated QEF is identical), and
- **(c)** uses the **same camera, `eps_px`, and collapse-hysteresis set** as the full build.

Then the boundary cells produce **bit-identical vertices** to the cached mesh → seam-
coincident → crack-free. The box expansion in (a)/(b) is bounded by the local cell size, so
the cost bound from the previous section holds.

### The trap: align to the *collapsed* size, not a single enclosing node

The naïve reading of (a) — "use the smallest octree **node** that encloses the edit" — is
**wrong, and reintroduces exactly the boundary pathology we set out to kill.** An edit landing
on the root split plane has no small enclosing node; its smallest enclosing node is the whole
root → a full rebuild. That would make the half-world boundary special again.

The fix: the patch box must be aligned to the **local displayed cell size**, not to a single
node. Near the player the displayed cells are fine (the clipmap is player-centred, so the root
centre is the *finest* region), so an edit there — including one dead on the root centre plane
— aligns to small cells and stays cheap. The boundary is non-special precisely because cell
*size* is a function of *distance from camera*, not of position in the tree.

But the displayed size is **error-driven** — a cell may be collapsed *coarser* than the
clipmap floor `F`, and we don't know how coarse without inspecting the cache. So:

- **Carry the cell size per triangle.** Today `_last_tri_owners` is origin-only; add a parallel
  **per-triangle owner cell *size*** (`_last_tri_owner_sizes`), threaded through the splicer and
  the cache (`_cache_owner_sizes`). Then the splice reads the **max owner size of cached
  triangles overlapping the edit box**, and aligns/expands its sub-box to whole cells of that
  size + a one-cell apron. That makes (a)/(b) exact against *what is actually on screen*, not a
  guess. This per-triangle size is a B1 prerequisite, independently testable.

### What it actually took (verified by the gate test)

Getting the sub-octree to reproduce the full build across a LOD transition needed **three**
things together — each found by the gate test (`test_dc_lod_splice.gd`) going from cracked to
clean. The first alone left big cracks; all three give an exact match (0 new boundary edges):

1. **Iterative sub-box alignment.** Align to the max displayed cell size overlapping the
   *whole sub-box* (core + apron + the pow2-rounded root), and **iterate** — aligning to a
   coarser size can pull in coarser-still cells. Aligning only to the core box (the first
   attempt) leaves coarser apron cells straddling the boundary → cracks.
2. **Cap collapse at the local cell size.** The sub-octree root rarely lands on a multiple of
   its own size, so its subdivision lattice is *offset* from the full octree's — and any
   collapse **coarser than `align_cell`** lands off the cache's lattice and cracks. Pass
   `max_leaf = align_cell` (a new `mesh_clipmap` param) so the splice never collapses coarser
   than what's already displayed there. This is also exactly B1's intent — "mesh at the local
   LOD, no coarser" — so it's the right rule, not a patch. (This is why "smallest enclosing
   node" is wrong *and* unnecessary: cap the collapse instead of growing the box.)
3. **A two-cell apron.** The edge-ownership ring (`owns_edge`) at a coarse cell needs **two**
   cells of context on each side, not one. `apron = 2 * max(_EDIT_APRON, align_cell)`. One cell
   mis-owns a handful of seam edges (small but real cracks).

Plus the collapse-set clear must cover the **octree root range** (not the emit box), so the
apron cells re-decide fresh too.

### Concurrency: serialize the collapse-set, don't share it live

(c) needs the splice to reuse the full build's collapse-hysteresis `HashSet`. The full build
(`_mesher`) and splice (`_splice_mesher`) currently run on **separate workers** — sharing a
mutable set across them is a data race. Resolution: **serialize** — only dispatch a splice when
no full build is in flight (`_task_id == -1`; edits during a build already re-queue via
`_edits_during_build`), and run the splice on the **same `_mesher`** so it inherits the set.
Full builds become rare under B1, so the lost concurrency costs nothing. The splice runs
**incremental** on the set: clear the entries inside its sub-box range, re-mesh (which re-adds
only those that still collapse), and **do not swap** prev/curr — so cells outside the box keep
their history and box cells are refreshed.

## Build sequence

### B1 — Multi-LOD splice (kills the edit latency) — **build now**

- **C++ [`dc_octree_mesher.cpp`](../../../engine/voxel_dc/dc_octree_mesher.cpp):** `mesh_subregion`
  currently forces `error_driven = false` over a single uniform level. Change it to run the
  **same error-driven build as `mesh_clipmap`** over the patch's expanded box, with
  `emit_filter` on (the emit-box machinery already exists). New inputs it needs: the clipmap
  levels, camera (lattice), `proj`, `eps_px`, and the shared collapse-set. Most of the work is
  *sharing* the full build's path, not new code — `accumulate`, `emit_filter`, and the
  point-location stitch are all already there.
- **Manager [`dc_terrain_manager.gd`](../../../scripts/dc/dc_terrain_manager.gd):** in
  `_dispatch_splice`, compute the local clipmap level(s) the edit box overlaps, **snap-expand
  to whole coarse cells + one-cell apron**, read the store at each level's resolution, and
  dispatch with the shared collapse-set. **Delete the `off_center > fine_half` fallback.**
  **KEEP `uniform_core=true` (corrected scoping).** Dropping the fine core belongs to **B2**, not
  B1: doing it in B1 made flat near-terrain error-driven *coarse*, so a part on flat ground had to
  align its splice to coarse cells, `apron = 2*align` fed a growing box into coarser LOD still, and
  a 2×2×6 block ballooned to span 176 (> the 96 cap) → the ~5s full rebuild. With the fine core
  kept, near edits land in uniform fine LOD → small box → splice; B1's multi-LOD machinery still
  handles edits at/over the fine-core boundary.
- **Shared state:** `_mesher` (full build) owns the collapse-hysteresis `HashSet`; the splice
  uses a separate `_splice_mesher`. Plumb **one shared set** so boundary cells collapse
  identically (requirement (c) above).
- **Splicer:** unchanged — it is already AABB-based, so the invariant is already honoured.
- **Test:** the new guard is a **crack-free splice across a LOD transition** (extend
  `test_dc_incremental_splice` + the watertight assert in `test_dc_octree_mesher`). Validate
  on real godot_voxel terrain, **not** an analytic field — see [[dc-sdf-not-unit-distance]]
  and [[validate-on-faithful-field]] (a raw-field test once hid a prune bug that deleted 45 %
  of the surface).

This is the bulk of the work, almost all in the mesher + the edit dispatch. It alone fixes
"edits slow to show up" at any distance, and it makes the splice the primary meshing path —
the "single-mesher consolidation" already noted as deferred cleanup.

### B2 — Budget-driven `eps_px` (the dynamic core) — **thin first cut**

`eps_px` (screen-error collapse threshold) is a constant today. Make it a **runtime controller**
against a hardware budget: after each build, read the cost (the per-edit / full-rebuild timing
instrumentation already in `dc_terrain_manager.gd` is the sensor — `WORK` ms or triangle
count), and nudge `eps_px` toward the budget, damped (the collapse already has hysteresis, so
it won't thrash). Coarsen when over budget, refine when under.

Combined with B1 dropping `uniform_core`, **the fine core ceases to exist as a constant** —
detail everywhere is emergent from screen-error, and screen-error self-tunes to the silicon
(more detail on a fast GPU, less on a slow one, no config). `LEVEL_DIM` demotes from operating
point to a max-depth bound — the legitimate "API-shape" kind of constant. First cut: nudge
slowly and let a meaningful change ride in on the next natural rebuild; full incremental
re-LOD is B3.

### B3 — Incremental LOD on camera move (retire full rebuilds) — **deferred, recorded**

Today the whole clipmap full-rebuilds when the follow target drifts > `RECENTER_DISTANCE`
(8 m). The endgame is to replace that with: as the camera moves, **diff the collapse-set** and
**re-splice only the cells whose LOD decision flipped**, reusing B1's patch machinery (a LOD
flip is just a "re-mesh this box" event, identical in shape to an edit). Then there are **no
full rebuilds, ever**, except first load / teleport.

This is the *write-once-mesh → live-mesh* shift and the largest piece. It is the natural
completion of [[edits-first-class]] (edited content must render identically to generated
terrain at every LOD, including as the LOD changes under camera motion). **Deferred** because
B1 already solves the symptom we hit; recorded here so the path isn't lost.

**B3 requires the world-anchored octree ([`10-adaptive-octree-substrate.md`](10-adaptive-octree-substrate.md)).**
The current render is a *player-centred clipmap snapped to a 16 m grid*: to follow you it
**re-snaps the root** (shifts the whole lattice frame by a coarse cell) every time you drift, so
every cell lands at a new lattice position — i.e. *everything* "changed", which is exactly why a
move triggers a full rebuild. You cannot diff-and-re-splice across a frame shift. The collapse-set
diff B3 wants only makes sense when cells sit at **fixed world positions** and a move changes only
*which LOD* a fixed cell is at — that is precisely the doc-10 substrate. So **B3 is not a tweak to
the clipmap; B3 is doc 10** (persistent world-fixed adaptive octree) **plus** the collapse-diff
re-splice on top. That's the architectural step, sized like B1's, not a quick follow-on.

## Recommended cut line & risks

- **B1 now** (fixes the real complaint), **B2 thin** (delivers the dynamic core cheaply; the
  sensor already exists), **B3 later** (endgame, worth it only once B1/B2 are proven).
- **The one place bugs hide:** the crack-free boundary across a LOD step — specifically the
  shared collapse-set and subtree-completeness (requirements (b)/(c)). The LOD-straddling
  watertight test on real terrain is the gate. Related veterans: [[dc-thin-feature-collapse-bug]],
  [[dc-no-balance-pass]], [[edit-remesh-padding-gap]].
- **Diagnostics already in place:** the per-edit trace (`edit→view … wait/sched/WORK/detect/apply`)
  and the `DC FULL rebuild … ms` line, both gated on the perf overlay being shown. These both
  *prove the problem* (every edit was a fallback) and *size the prize* (the rebuild ms B1
  removes), and B2's controller reuses them as its sensor.
