# Persistent Octree Substrate — staged plan (B3 / doc-10 completion)

## START HERE — next session (finish 16 = build the world-fixed incremental octree)

**Read `docs/MANIFESTO.md` in full first, then "THE GOAL" below.** The previous session fell into the
exact Enterprise traps the manifesto forbids and you must not repeat:
- proposed *defer-the-hard-part / ship-current-state / rewrite-later* (the habit, not the thesis);
- chased **worker-thread wall-clock** (the move rebuild) while framerate was 300fps — manifesto #8 says
  leave wall-clock on a worker alone and **never** trade correctness for it;
- shipped a **gradient surface-prune that broke watertightness** — the *literal* cautionary tale in #8.
The world-fixed octree is **enabling STRUCTURE** (mandatory, never deferrable), not an optimization. The
move rebuild's staleness (terrain lags seconds behind you) is a **correctness** failure. Correctness first.

**The hump, precisely:** movement triggers a FULL rebuild of a **camera-centered** clipmap octree (~4.8s).
Root cause: the clipmap re-centers its data on the camera every build (`Clipmap::level_index`/`value` are
distance-from-`center`; `_dispatch` re-snaps the octree root to the player). A move = "all data moved" =
rebuild. The fix is to make **data world-fixed** and the **build incremental** (build only the leading
band, reuse the interior). That's THE GOAL below.

**Do this — decisively, in small tested steps toward the FULL end (never a smaller end):**
1. **DECIDED (2026-06-15): option (i) — retire the clipmap data model.** One world-fixed octree
   sampling the field directly; no concentric clipmap levels, no geomorph. **Enabler (the decisive
   find):** `EditStore::sample(Vector3)` is already a C++ method (generator + edits, worker-safe), so the
   7 concentric 129³ clipmap grids + `fill_region` batching are a **godot_voxel-era vestige** — the
   octree can sample any world point at any resolution on demand. World-anchoring + incremental growth
   fall out cleanly; world-anchoring *within* the clipmap (ii) is strictly more awkward and was rejected.
   Per manifesto "one field / one representation / the grid is a world-fixed spatial database" (#7) and
   "don't optimize the wrong structure" (Enterprise trap).

   **Sub-decision — the build is BOTTOM-UP EXACT, not top-down lazy-refine.** A top-down refine criterion
   (split a cell by its own coarse-corner residual) is a *compromise*: it decides from a coarse sample, so
   a sub-cell spire that threads between the corners is silently lost — the manifesto's "looks right until
   it doesn't." Keep the proven path: build to the fine floor wherever there is surface (the EXACT min/max
   prune **cannot** miss a crossing), accumulate fine QEF up the tree, collapse by screen-error from real
   fine data. The feasibility worry (a fine floor over a ~1 km horizon = tens of millions of cells) is
   **worker-thread wall-clock that scales with DETAIL, never framerate or world size** → manifesto #8 says
   do not trade correctness for it; and incremental growth builds only the thin leading-edge band per move.
   The "refine criterion" chicken-and-egg only exists if you go top-down — so don't. (Top-down→GPU is a
   *later* hardware-driven candidate, doc 16 tail, not now.)
2. **Build incrementally.** Each step gated by ALL of: watertight on real heightfield terrain **WITH
   collapse** (`error_driven=true` — the test gap that bit last time; see `test/test_dc_real_terrain.gd`);
   **interior byte-identical** before/after a small move (the incremental-correctness gate — an
   incremental build must equal a from-scratch build); full GUT suite green; and in-game `dcinval` shows
   a **thin band** re-meshed on a move, not the whole-vicinity box.

**Foundations already built — REUSE, don't rebuild (all on `feat/dc-persistent-octree-cache`):**
- **Persistent octree** — `DCOctreePersist` pimpl in `engine/voxel_dc/dc_octree_mesher.cpp`;
  `remesh(camera, proj, eps)` re-walks it (re-collapse, no field sample), tested byte-identical to a
  fresh build. `accumulate_qef()` (field, once) is split from `collapse_pass()` (camera, re-runnable).
- **EXACT surface-sparse prune** — `Level::build_mip`/`surface_free` + `Clipmap::surface_free`; on when
  `prune_safety>0`; watertight WITH collapse. (The gradient prune was the watertightness wound — deleted.)
- **Scroll-fill** — `EditStore::fill_region(prev, prev_origin, dirty_origin, dirty_size)` reuses the
  overlap, samples only the scrolled-in shell + edited box. Manager: `_scroll_buffers`/`_scroll_wcs`/`_dirty_*`.
- **Async in-place remesh** + build/remesh/splice **serialized** on the shared `_mesher`
  (`_dispatch_remesh`/`_remesh_job`/`_finish_remesh`).
- **move→remesh** — `_build_center`, `REMESH_DISTANCE`(2m)/`REBUILD_DISTANCE`(12m): moves re-collapse the
  retained octree; a full rebuild fires only past 12m. **That 12m rebuild is the remaining cost Stage B
  eliminates.**

**Read to orient:** `Level`/`Clipmap` structs (`dc_octree_mesher.cpp` ~L26–160) = the camera-centered
data model to replace; `_dispatch`/`_mesh_job` (`dc_terrain_manager.gd`) = where the clipmap levels are
built + the root re-snapped; `docs/roadmap/design/10-adaptive-octree-substrate.md` = the substrate vision.

**Loose ends (NOT priorities — the rewrite subsumes them):** prune only got 8.7→4.8s (≈1.8×, not ~20× —
likely the per-rebuild mip allocation over 7×129³, or steep terrain having more surface cells); the
`No vertices… immediate_mesh.cpp:150` warning (empty-surface draw, probably a debug overlay); distant-edit
detail loss (coarse clipmap undersampling — gone once data resolution is world-fixed).

---

## Stage A scaffold — LANDED (2026-06-15): the direct-sampling seam

The world-fixed octree's foundation is in (decision + scaffold, GUT-green, live render untouched):
- **`SdfSource` seam** (`dc_octree_mesher.cpp`) — the octree no longer hard-codes the `Clipmap`; it
  holds a `const SdfSource *src` (value/gradient/target_cell_size/surface_free/index_prefer_explicit/
  is_finest_level). `Clipmap` is now one impl (math unchanged → the live clipmap render is **byte-
  identical**, guarded by the full DC suite still green). `DCOctreePersist` holds the `Clipmap` beside
  the retained octree.
- **`EditStoreSource`** — samples `EditStore::sample`/`material_at` DIRECTLY (the enabler), world-anchored
  (1 lattice unit = base_cell m; lattice (0,0,0) at world_origin). No concentric levels, no geomorph.
  `surface_free` abstains for now → dense build to floor (exact sparse prune over direct sampling = a
  later stage; per #8 the extra worker cost is detail-scaling, not framerate).
- **`mesh_world(store, world_origin, depth, base_cell, camera, proj, eps_px, error_driven, palette)`** —
  builds + meshes ONE world-fixed octree over `EditStoreSource`, bottom-up exact (build→accumulate→
  screen-error collapse). Bound; the live render still runs `mesh_clipmap` until this is trusted.
- **Tests** (`test/test_dc_world_octree.gd`) — on the REAL Phase-B `EditStore` terrain: (1) no-collapse
  is **crack-free** (interior boundary edges == 0) AND its audit equals the trusted baked-grid path
  (faithful direct sampling); (2) WITH collapse produces a finite surface, no inf/nan verts; (3) direct
  sampling == baked-grid topology (same vertex count). nonmanifold isn't asserted ==0 (this region has
  zero-area grazing-corner degenerates — the known deferred artifact — in BOTH paths; we assert
  equivalence). Crack-free-WITH-collapse on a cut region isn't headlessly auditable (collapsed boundary
  cells defeat the rim test, as the trusted suite already acknowledges) → it's the in-game `dcinval`
  GUI gate.

**Persistence — LANDED (2026-06-15, follow-up):** `mesh_world` now RETAINS its octree in `DCOctreePersist`
(holding the `EditStoreSource` + a `Ref<EditStore>` so `oct.src` stays valid), so the existing
`remesh(camera, proj, eps)` re-collapses the world octree against a new camera with **no field resample**.
Test: a re-walk at the build camera reproduces it byte-for-byte; a nearer re-walk equals a fresh build
there and keeps more detail. This is the prerequisite for incremental movement.

**Vehicle decision (2026-06-15):** THE GOAL rides on `DCOctreeMesher` (it has the GOAL-mandatory
screen-error LOD + crack-free meshing that `SparseVoxelOctree`/`DcSubstratePreview` lacks — SVO is
distance-graded, view-independent). The world-fixed *manager* will MODEL its re-root/refine/edit-dirty
cadence on the proven `DcSubstratePreview` GDScript, and the `dcgen`/SVO render is retired once
`mesh_world` supersedes it (least-duplication path — we delete a parallel mesher, not copy the
screen-error core into SVO). SVO may remain as a Phase-B *storage* oracle.

**Stage B incremental growth — LANDED (2026-06-15, headless): B0 window + B1 grow/evict.**
- **B0 — windowed build.** `mesh_world` gained `win_min`/`win_max` (WORLD lattice): a large root spans the
  roam region while the build descends only the cells overlapping the window (the existing `build_box`),
  marking the rest *absent* (no QEF, no vertex, not meshed — the window edge is the resident mesh's open
  rim). New `window_mode` flag gates the absent marking so the clipmap **splice is untouched** (it needs
  its out-of-box cells meshed to stitch the patch rim). Gate: a whole-root window == the no-window build
  byte-for-byte; a sub-window builds strictly less.
- **B1 — incremental grow + evict (the core).** `grow_world(camera,proj,eps,win_min,win_max)` re-windows
  the RETAINED octree: `reconcile(0)` grafts cells that entered (`grow_subtree` + `accumulate_qef` sample
  ONLY the new band) and evicts cells that left (`kill_subtree` clears the orphaned subtree so the flat-
  array mesh loops skip it); `reaccumulate(0)` rolls ancestor QEFs up from cached children with **no field
  sampling**; then `recollapse_and_mesh`. **Gate (the brief's): `grow A→B` == fresh `mesh_world` of B —
  same surface + winding — while sampling only the leading edge** (`get_last_build_sample_count` proves the
  interior wasn't resampled). Round-trip A→B→A is lossless. The "byte-identical" gate compares the triangle
  set order-independently: the incremental tree's array layout differs (grown cells appended, evicted ones
  leaked), so vertex *order* differs, but positions are bit-identical and the surface matches exactly.
  Tests: `test/test_dc_world_octree.gd` (`test_grow_world_equals_fresh_build`, `..._round_trip_is_lossless`).

- **B1b — bounded resident set (free-list).** `kill_subtree` now returns evicted slots to a `free_list`
  the next grow's `alloc_cell` reuses, so the cell array plateaus across a traverse instead of leaking.
  Gate (`test_grow_world_bounds_resident_set`): a 22-move window sweep across the root grows storage only
  12073→14793 (+22%) — vs ~278k if it leaked — and the final surface still matches a fresh build.

**NEXT:** the exact surface-sparse prune over direct sampling + graded data floor for horizon coverage (the
O(volume) wall — `EditStoreSource::surface_free` currently abstains → dense build to floor; the hard part is
there is no pre-baked grid to mip against, unlike the clipmap), then a `dcworld` manager (modeled on
`DcSubstratePreview`) wires `mesh_world` + `grow_world` as the live render — the first GPU eyes on this path
(`dcinval` thin-band gate) — and retires the clipmap + geomorph + the SVO `dcgen` path.

## THE GOAL — world-fixed incremental octree (no compromise)

The correct end state, per the manifesto (one field / one representation / persists everywhere / the
grid is a world-fixed spatial database): **a single persistent octree anchored to WORLD coordinates**.
Cells sit at fixed world positions and keep their triangles. The two things that are conflated today —
*where the data is fine* and *where we draw fine triangles* — are **separated**:
- **Data resolution is world-fixed**: fine where there is detail/edits, fixed in space, so fine data
  exists *ahead* of the camera because terrain is there, not because you're looking at it.
- **Render LOD is screen-error** (camera-driven `we·proj/dist`) — already working (Stage 1).

So **moving = re-collapse over data that's already fine ahead + build only the leading-edge band**;
the interior octree (cells, QEFs, triangles) is reused. No full rebuild on movement. This retires the
camera-centered clipmap levels and the geomorph blend (the screen-error octree already stitches LOD
jumps crack-free via point-location).

**Why this is mandatory, not an optimization (manifesto #8):** the move rebuild's staleness is a
*correctness* failure (the displayed terrain lags seconds behind you), and a camera-centered data model
is the wrong *structure*. This is enabling structure, not wall-clock chasing. The session's retention,
scroll-fill, surface-sparse prune, and `remesh()` are its foundations — kept.

**Staged build (small reversible steps toward the FULL end — never a smaller end):**
- **A — World-anchor the octree/data window** so cells hold fixed world positions as the camera roams a
  resident window (prerequisite for reuse). Retire the camera-recentred root.
- **B — Incremental growth**: on a move, build only the leading-edge cells from the (scrolled) world-
  fixed data and graft into the retained octree; evict the trailing edge. Interior reused.
- **C — Retire clipmap levels + geomorph**: one world-fixed adaptive data source feeding the octree;
  data resolution driven by detail, not camera distance.
- Each stage: tested (watertight + interior-byte-identical-on-move), shippable, leaves the game working.

---

## Progress at a glance (single source of truth — update on every commit)

**Stage 1 — Screen-error criterion — ✓ DONE** (merged to master via `feat/dc-screen-error-lod`)
- [x] `camera`/`proj`/`eps_px` restored in `mesh_clipmap`; collapse on `we·proj/dist > eps_px`
- [x] Manager computes camera-lattice + proj from the live `Camera3D`; threaded to worker + splice
- [x] B2 budget tunes `eps_px` (default on); FOV-change re-mesh trigger
- [x] Test knobs: `fov` / `dceps` / `dccore` console cmds; fullscreen + uncapped-fps + vsync-off defaults
- [x] Full GUT suite green (215 tests) incl. a camera/FOV-dependence test
- [x] **In-game validation** — screen-error confirmed: flat coarsens, detail/near stays fine, telescope refines distant

**Stage 2 — Persistent node cache + invalidation** *(the movement payoff)* — branch `feat/dc-persistent-octree-cache`
Approach B (persistent C++ octree — "octree survives frames"). The field-derived per-node QEF is built
once; the camera-derived collapse verdict is re-decided cheaply per move. Approach A (GDScript displayed-
leaf cache) was rejected: it can't predict collapse-on-recede without retaining internal nodes.
- [x] **2a** — split `accumulate()` → `accumulate_qef()` + `collapse_pass()`; retain the octree on `DCOctreeMesher` (pimpl); `remesh(camera,proj,eps)` re-walk entry; test proves a re-walk == a fresh build at that camera (byte-identical)
- [x] **2c — async in-place remesh** (uses the retained octree — 2a). FOV/eps changes re-collapse the retained tree **on a worker** (`DCOctreeMesher.remesh`, no rebuild, no field sampling), applied next frame. First tried synchronous (hitched + made the budget oscillate — a lag spike per interval, caught in GUI test) → moved to the worker. The build / remesh / splice jobs are now **serialized** on the shared `_mesher` (also fixes a latent build-while-splice race). So eps/budget tuning and zoom no longer trigger a "DC FULL rebuild". (Retained octree is now load-bearing — kept.)
- [x] **2d** (edit half) — edits already re-mesh only the touched region via the build-box splice (no change needed); FOV/resize covered by 2c's `remesh`.

**PERF FINDING (the big one):** the move rebuild was **8.7 SECONDS** (measured in-game, 7 LOD levels,
~120k verts) — NOT the field sampling, but the **dense bottom-up build**: it descends EVERY cell in the
fine region to the data floor (~2M cells at ±16m / 0.25m) and samples all of them, even though terrain
is a thin sheet and ~95% are empty. Scroll-fill / remesh / retention all missed this — they optimized
sampling + stationary re-collapse, not the dense build. 300fps misled me (it's the main thread; the 8.7s
is the worker, so the terrain just lagged seconds behind movement).
- [x] **surface-sparse build — EXACT min/max prune (THE perf fix, done right):** the build skips a cell
  only when its actual grid samples are all one sign (no zero-crossing), via a **min/max mip** of each
  level's grid — O(1)/node, and it physically cannot miss a sub-cell ridge, so it never over-prunes. This
  replaced the gradient-estimate prune that shipped degenerate geometry (1st attempt). Default ON
  (`dcprune 0` = dense, to compare). Guarded by a watertight test WITH collapse (`error_driven=true`) on
  the real heightfield terrain — pruned+collapse surface == dense+collapse surface, all verts finite (the
  test gap that let the gradient version slip through). Should cut the 8.7s dense build by ~20-40×.
  **GUI-verify the rebuild ms + geometry.**
- [x] **2b/3 — scroll-fill the move rebuild** *(secondary win)*: a recenter re-samples only the shell that scrolled in, reusing the previous build's grids via `EditStore.fill_region`. (Cuts the *sampling*; the prune cuts the *build* — together they attack the move rebuild from both sides.)
- [x] **2b/3 — scroll-fill the move rebuild** *(the move-latency win)*: a recenter now re-samples only the shell that scrolled in, reusing the previous build's per-level grids via `EditStore.fill_region` (the proven mechanism the collision manager uses) — the dominant generator cost is cut. Edits clear the buffers (next build re-samples, no stale reuse). Test: a scrolled rebuild == a full-sample rebuild byte-for-byte. *(This is the pragmatic win; the full world-anchored-octree-that-keeps-interior-triangles is deferred — not needed at current scale, and the scroll-fill captures the latency.)*
- [x] **2e** — correctness tests landed (remesh==fresh-build; set_eps in-place; scroll==full-sample). Visual `dcinval` thin-band check is a GUI step.

- [x] **edit lag — FIXED:** the splice re-sampled ALL levels in full (~10M evals) just to mesh a tiny box — that was the ~100ms. Now it reuses the last build's grids (`_scroll_buffers`, same frame → shift 0) and re-samples only the dirty (edited) box via `fill_region`. Unified dirty-box model: edits accumulate an AABB instead of clearing the buffers, so both the move rebuild and the splice re-sample only what changed; a full build re-bakes + resets the dirty box. (The dirty box covers ALL pending edits, so a splice's apron can't reuse a stale neighbouring edit.)

**Stage 3 — Top-down lazy build** *(speed)* — **merged into 2b/3** (scroll-fill) above.

**Stage 4 — Eviction** *(bound the resident set)* — **N/A in the current architecture.** The resident set is already bounded: the camera-centered clipmap is a FIXED-size window (LEVELS × LEVEL_DIM³), re-used via scroll. Eviction only becomes a thing if we ever build the full world-anchored *unbounded* octree (deferred — scroll-fill captured the latency without it). Nothing to evict today.

**Stage 5 — Retire the godot_voxel render fallback** *(cleanup)* — **deferred on purpose.** The `dcsolo` / godot_voxel per-block render is the comparison baseline, and Robert keeps old paths to compare against (see the project preference). Retire it later, deliberately, once DC is trusted across more scenarios — not now.

**NET (this branch, `feat/dc-persistent-octree-cache`):** the persistent octree's payoff is realized as *latency* — moves and edits re-sample only what changed (scroll + dirty-box), and FOV/zoom/eps re-collapse with no field reads. The headline "octree literally survives frames and keeps interior triangles" full rewrite is deferred (no scale pressure); the scroll-fill delivers the same user-visible win.

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

