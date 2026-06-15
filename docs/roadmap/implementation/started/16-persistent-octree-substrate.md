# Persistent Octree Substrate — staged plan (B3 / doc-10 completion)

## Progress at a glance (single source of truth — update on every commit)

Branch: `feat/dc-screen-error-lod` (not yet merged to master).

**Stage 1 — Screen-error criterion**
- [x] `camera`/`proj`/`eps_px` restored in `mesh_clipmap`; collapse on `we·proj/dist > eps_px`
- [x] Manager computes camera-lattice + proj from the live `Camera3D`; threaded to worker + splice
- [x] B2 budget tunes `eps_px` (default on); FOV-change re-mesh trigger
- [x] Test knobs: `fov` / `dceps` / `dccore` console cmds; fullscreen + uncapped-fps + vsync-off defaults
- [x] Full GUT suite green (215 tests) incl. a camera/FOV-dependence test
- [ ] **In-game validation** — tune ~2px via `dceps`, confirm `fov` (telescope) refines distant terrain, and walking coarsens-behind / refines-ahead (needs GPU eyes)

**Stage 2 — Persistent node cache + invalidation** *(the movement payoff)*
- [ ] not started

**Stage 3 — Top-down lazy build** *(speed)*
- [ ] not started

**Stage 4 — Eviction** *(bound the resident set)*
- [ ] not started

**Stage 5 — Retire the full-rebuild + godot_voxel render fallback**
- [ ] not started

---

*The B1-style stage plan for the one piece of [doc 10](../../design/10-adaptive-octree-substrate.md)
that's still missing: making the render octree **persistent and world-fixed** so movement refines
it **incrementally** instead of triggering a full rebuild. This is "B3" from
[doc 13](../../design/13-incremental-lod-splice.md). Each stage ships independently, stays tested, and
leaves the game working — the current clipmap keeps rendering until a stage is trusted.*

## CURRENT PLAN — read this first (2026-06-15)

**LOD = screen-space error.** A cell stays refined while its triangles project to **> ~2px**, merges
when they don't (so far terrain coarsens; a telescope/zoom narrows FOV → distant terrain grows back
over 2px → refines). Built as a **lazy, cached, persistent octree**: coarse by default, refine on
demand where the field has detail AND it's visible, cache each **node**'s result (triangles +
subdivide verdict), invalidate per cause — **move**, **edit**, **FOV**, **window resolution**.

**Canonical stages (this supersedes every other stage list in this file):**
1. **Screen-error criterion** — restore `camera`/`proj`, collapse on `we·proj/dist > ~2px`, re-mesh on
   FOV change as well as drift. Eager; validates the 2px + telescopes in-game.
   *(code landed — `camera`/`proj`/`eps_px` back in `mesh_clipmap`, screen-error collapse, B2 tunes
   `eps_px`, FOV-change re-mesh; full GUT suite green incl. a camera/FOV-dependence test. PENDING:
   in-game 2px tune + telescope check — needs GPU eyes.)*
2. **Persistent node cache + invalidation** — octree survives frames; a move re-tests screen-error per
   node, re-meshes only crossers; edits dirty touched nodes; FOV/resize re-test all. *(the payoff)*
3. **Top-down lazy build** — refine on demand instead of meshing every cell to the floor. *(speed, last)*
4. **Eviction** — bound the resident set (the "### Stage 2 — Eviction" section below).
5. **Retire the full-rebuild + godot_voxel render fallback** (the "### Stage 3" section below).

**Already done this session (commits `2539bb0`→`956f455`):** the crack-free **build-box splice**, the
**thin-gap winding fix**, **examine mode** (+Ctrl+E), and the **dead-machinery cleanup**.

**SUPERSEDED — read as history, not plan:** everything below framed as *necessity / camera-independent
/ distance-irrelevant / world-fixed grid*. The build-box *finding* is real and done; the LOD *criterion*
reversed from camera-independent "necessity" back to screen-error (a confused requirement, corrected).

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

## DIRECTION CORRECTION (supersedes the "necessity, not distance" section below)
The camera-INDEPENDENT "necessity" LOD was a detour (a confused requirement, since corrected). The
real model is **screen-space error**: a cell stays refined while its triangles project to **more than
~2px**, and merges when they don't — so far terrain coarsens, and a **telescope/zoom (narrow FOV)**
magnifies distant terrain back over 2px and refines it. Implemented as a **lazy, cached, persistent
octree**: coarse by default, refine on demand where the field has detail AND it's visible, cache each
NODE's result (its triangles + subdivide verdict), invalidate per cause — **move** (distances change),
**edit** (field changes), **FOV** (zoom/telescope), **window resolution**. This brings `proj`/FOV back
into the collapse threshold (`we · proj/dist` vs ~2px); the QEF residual, build-box, and winding work
all carry. The "RESOLVED: necessity, not distance" section further down is OBSOLETE — ignore it.

**Staged build:**
1. **Screen-error criterion** — restore the projected threshold (keep refined while `we·proj/dist >
   ~2px`), re-add `camera`/`proj`, trigger a re-mesh on FOV change as well as drift. Eager (still
   rebuilds on recenter) but makes the LOD camera-responsive; tune the 2px in-game. Small.
2. **Persistent node cache + invalidation** — the octree survives across frames; each node caches its
   mesh + verdict; a move re-tests the cheap screen-error per node and re-meshes only the crossers; an
   edit dirties touched nodes; FOV/resize re-tests all. The incremental-movement payoff + world-anchor.
3. **Top-down lazy build** — refine downward on demand instead of meshing every cell to the floor.
   Pure speed; last, since we're at <1ms/frame.

Longer term this is a candidate to move onto the GPU (resident sparse SDF + compute DC, screen-error
selection), which the hardware (32G VRAM) suits — deferred until CPU meshing actually saturates (it
isn't close), and the same algorithm ports over.

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

