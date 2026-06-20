# Continuous Incremental Meshing (no full rebuilds except re-root)

*The design spec for making the world-octree render **fully incremental and
continuous**: edits patch only the edited box, refinement spreads over frames at
a per-frame budget, and the worst-looking cells refine first. The successor to
[`13-incremental-lod-splice.md`](13-incremental-lod-splice.md) (whose B1 splice
was clipmap-era and deleted, B2 budget controller shipped, B3 became the
world-octree) in the world-fixed octree of
[`17` (impl)](../implementation/done/17-world-octree-to-production.md) /
[`10-adaptive-octree-substrate.md`](10-adaptive-octree-substrate.md). Motivated by
the same principle as doc 13: the only legitimate limit is the hardware, so per-
frame cost should be a runtime budget, not an emergent spike.*

## TL;DR

The world-octree reuses the retained tree on **moves and eps changes**
(`grow_world` re-meshes only the band it touched), but two costs remain O(window):

1. **Edits throw the whole tree out.** An edit sets `_dirty`, which routes to
   `mesh_world` — and `mesh_world` does `memdelete(_persist)` then rebuilds from
   scratch, **re-sampling every leaf in the window**. A 2 m edit re-samples the
   whole 256 m window. That is the lag spike.
2. **Refinement is batched.** The budget controller nudges `eps_px`; each step
   fires **one grow that re-meshes the entire changed band at once** → discrete
   spikes bounded by `mesh_ceil` (500 ms), not a smooth bloom.

Four innovations close both:

- **(3a) Per-cell solve caching — SHIPPED.** The QEF residual and the emitted
  vertex are pure functions of a cell's accumulated QEF, so a grow re-solves only
  the cells whose QEF changed. Turns per-grow solve cost from O(window) → O(band).
  Byte-identical by construction.
- **(E) Incremental edits.** Reconcile only the edit box against the changed
  field instead of rebuilding the window. Reuses 3a's dirty-set; crack-free for
  free (we mutate the retained tree in place — doc 13's separate-patch boundary
  problem does not arise). O(edit) instead of O(window).
- **(C) Continuous budgeted refinement.** Drain a **per-frame cell budget** from a
  refinement worklist that persists across frames, instead of meshing a whole eps-
  step band in one grow. Per-frame cost bounded by construction.
- **(P) Priority-by-error.** Order the worklist as a **max-heap on screen-error**
  (`we·proj/dist`, already computed in collapse), so the worst-looking cells
  refine first — best visual gain per unit work.
- **(3b) Persistent buffer + partial GPU update.** Stable per-leaf vertex slots
  and `RenderingServer` sub-range updates remove the residual O(window) emit-
  assembly + vertex-upload floor that 3a/E/C/P leave behind. **Measure-gated** —
  only worth its render-path risk if that floor still bites after the rest.

**End state:** per-frame mesh lag is bounded *always*; the only unavoidable full
rebuild is a **re-root** (the player leaves the root box — rare, and itself a
deferred incremental target).

**Vision framing (not just perf).** The coarse→fine bloom this machinery produces
— the world resolving *where the player directs attention* — is a **diegetic
dream-tell**, not an artifact to hide: in dreams, things don't resolve until you
look at them, which tells the player *"you are the center of the universe."* So
**P+ (refine toward gaze/motion) is the mechanic, not merely an optimisation**,
and the bloom's pacing is an aesthetic lever. The game is intended to **open in a
void** and let the world build coarsely + refine in front of the player. See
[[world-builds-on-attention-dream-tell]] and design doc 14 (consensus-reality);
the void-start must reconcile with the world-ready gate (the player likely floats
until the ground resolves — itself on-theme).

## Foundation (shipped): grow + 3a solve caches

`grow_world` (doc 17 P2.5) already re-meshes only the band a move/eps change
touched: `reconcile` grafts cells entering the window, evicts those leaving,
refines cells the camera approached and coarsens cells it receded from, matching
`build()`'s per-cell decision so the surface equals a fresh build there. Field
**sampling** was already incremental.

What stayed O(window) was the *solve* work after reconcile: `recollapse_and_mesh`
re-ran the QEF SVD in `collapse_test` (the screen-error residual) and in
`place_vertex` (the emitted vertex + material sample) for **every** cell, even
though only the band changed. **3a caches both on the `Cell`:**

- `we_cache` — `sqrt(qef.residual(solved vertex))`, the collapse screen-error
  numerator.
- `vpos_cache` / `vnorm_cache` / `vcol_cache` — the solved vertex.

Invalidation rides on a per-frame `dirty` bit: `reconcile`/`sample_leaf` set it
where they change a cell; `reaccumulate` propagates it to ancestors (a node re-
sums only when a child changed) and clears the `*_valid` flags exactly where the
accumulated QEF changed. Everywhere else the cached solve is reused. The O(window)
tree *walk* stays (it is cheap — a comparison and a flag write); the O(window)
*SVD solves* become O(band).

**Why it is byte-safe:** caching a deterministic function of `qef` and reusing it
when `qef` is unchanged produces identical output. All gate tests
(`grow==fresh`, `remesh` byte-identical, `parallel==serial`) pass unchanged.
`remesh` (collision, falling chunks) benefits too — it re-walks with a new camera
but unchanged QEFs, so every cached solve is reused. *(This rationale graduates
to [`architecture.md`](architecture.md) once the rest of this doc ships.)*

## E — Incremental edits (kill the rebuild spike)

### The opportunity

The edit footprint is already known: the bus `TerrainSdfChangedEvent` carries the
changed `cells`, and `EditStore::fill_region` already takes a dirty box. The
render handler currently **discards it** and sets `_dirty` → full rebuild
([`dc_world_preview.gd`](../../../scripts/dc/dc_world_preview.gd), "an edit in the
interior needs a full rebuild"). It doesn't have to.

### Why the world-octree makes this easy (doc 13's hard part disappears)

Doc 13's clipmap splice was hard because it meshed a **separate patch** on a
**separate mesher** and had to reproduce the full build's LOD + collapse-set at
the patch boundary bit-for-bit (the two-cell apron, the shared hysteresis set,
align-to-collapsed-size). **None of that applies here.** An incremental edit
mutates the **one retained tree in place**, then `recollapse_and_mesh` re-decides
the whole tree's collapse against the unchanged camera/eps (cheap, via 3a). The
result *is* a fresh build of the edited field — the crack-free guarantee is the
existing `grow==fresh` invariant, extended from floor changes to field changes. No
boundary stitch, no second mesher, no shared set.

### Mechanism

An edit differs from a move: a move changes a cell's *floor* (by distance); an
edit changes the *field values* and may **add surface where there was none** or
**remove it**. So incremental edit is a **field-dirty reconcile over the edit
box**:

1. **Update the prune accel over the edit box.** `surface_free` mips must reflect
   the edit or a newly-added surface gets pruned away (or a removed one lingers).
   Re-bake the accel over the box (the bake is far cheaper than the tree build);
   incremental accel update is a later refinement.
2. **Reconcile the edit box with a `field_dirty` AABB** — a new input distinct
   from the window/floor reconcile:
   - **Inside the box:** force re-sample present leaves (their field changed —
     today's reconcile reuses an unchanged-floor leaf without resampling; that is
     the one case that must change), and re-evaluate `want_leaf` so a cell
     **refines** where surface appeared and **coarsens/prunes** where it vanished.
   - **Outside the box:** unchanged — reused exactly as a no-floor-change move.
3. **`reaccumulate` + `recollapse_and_mesh`** as today — 3a bounds the re-solves
   to the dirtied band.

### Status (2026-06-20): implemented, gated, **pending a structural fix**

`edit_world` + `reconcile_edit` are implemented (`dc_octree_mesher.cpp`) and the
gate `test_edit_world_equals_fresh_build` is written. It is **pending**, not
green, because a *localized* edit box leaves ~6% of triangles differing near the
edit. The bug was driven into a corner by bisection:

- **A whole-window dirty box reproduces a fresh build EXACTLY** (0 diff), and a
  **no-op edit reproduces the retained mesh EXACTLY**. So `reconcile_edit` and the
  roll-up/emit are correct *in the large*.
- It is **NOT coverage**: the measured field-change bbox sits inside the padded
  box, and every changed-corner cell is re-sampled (leaf QEFs verified correct).
- It is **NOT the 3a caches** (forcing a full vertex/we recompute still differs)
  nor `reaccumulate`'s skip-opt (a full `accumulate_sums` roll-up still differs).

So it is a **`reconcile_edit`-vs-`build` STRUCTURAL mismatch over a sub-box**: for
the same edited field, a localized reconcile leaves the tree (which cells are
leaves, at which sizes) near the edit in a state that differs from what a fresh
`build()` produces — and only re-walking more of the window corrects it. The
prune is implicated (the structure difference is empty-cell pruning near the
edit), but a near-camera edit (fine accel) failed too, so it is not *only* accel
coarseness. **This is the open problem blocking E.** Likely shapes of the fix:
the reconcile box must cover the **prune-decision-change footprint**, not just the
field-change box; or `reconcile_edit` must re-derive a sub-box's structure
bit-identically to `build()` (the doc-13 align-to-cell lesson, now for *structure*
not *stitch*). Needs the tree dumped for the differing cells to pin precisely.

### Open questions (still flagged)

- **Accel granularity.** Re-bake the whole window accel (current) vs. incrementally
  update only the box's mips (true O(edit)). Tied to the prune-footprint question
  above — resolve together.
- **Edit box → octree alignment.** Snap the box to whole cells at the local
  displayed size (carry `_last_tri_owner_sizes`) so a refine/coarsen at its rim is
  decided on-lattice.

### Gate test

`grow_world` after an in-place edit == a fresh `mesh_world` of the edited field
(surface-equal, the doc-17 signature comparison), **and** `build_samples` ≈ the
edit box's cell count, not the window's (proving the interior was not resampled).
Validate on the faithful field, not an analytic one ([[validate-on-faithful-field]],
[[dc-sdf-not-unit-distance]]).

## C — Continuous budgeted refinement (smooth the bloom)

Today: lower `eps_px` → `_eps_dirty` → one grow re-meshes the whole changed band.
The work for an eps step is paid in a single frame.

Instead, make refinement a **worklist drained at a per-frame cell budget**:

- The controller still owns the *target* (`eps_px` from the frame-time + mesh-lag
  budget), but it sets a **goal**, not an instantaneous whole-band remesh.
- A **refinement worklist** holds cells whose displayed size is coarser than their
  graded floor wants (i.e. cells that *would* subdivide at the current `eps_px`).
- Each frame, pop up to **N cells** (the per-frame budget, sized to the frame-time
  headroom), `grow_subtree` them, and re-emit. Cells not yet reached stay coarse
  this frame and refine on a later one. The worklist persists across frames.
- Coarsening (camera receded, eps raised) is symmetric: a coarsen worklist, same
  budget.

The mesh lag per frame is then **bounded by the budget**, independent of how much
total refinement is pending — a held view blooms toward its floor over several
frames instead of one spike. This is the "idle progressive-refinement" the doc-17
P2 note anticipated. 3a makes each popped cell cheap; E means edits feed the same
worklist instead of rebuilding.

**Interaction with the controller:** the budget controller's job narrows from
"pick eps and pay the whole remesh" to "pick eps (the target detail) and pick the
per-frame cell budget (the spend rate)." Two knobs, both driven by the same
frame-time/mesh-lag sensors that exist today.

## P — Priority-by-error (refine the worst cells first)

The worklist in C is a *set*; make it a **priority queue keyed on screen-error**.
Each candidate cell's error is `we·proj/dist` — exactly the quantity
`collapse_test` already computes (and 3a now caches as `we_cache`). Pop the
**highest-error** cell each step:

- The most visually wrong cells (a coarse cell projecting large on screen, a
  near-camera feature) refine first; distant/flat cells wait.
- Best perceived-quality gain per unit budget — the bloom looks like it sharpens
  where you're looking, not in tree-walk order.

Implementation: a max-heap (or bucketed approximation) over the refinement
frontier, re-keyed as cells move/refine. The heap is maintained incrementally —
a refined cell's children are inserted with their own error; a cell that drops
below `eps_px` leaves the heap. Composes directly on C (C without P drains in
arbitrary order; P just orders the drain).

**Risk:** heap maintenance across moves is the bookkeeping cost. A bucketed
priority (a few error bands, FIFO within) is a cheaper approximation if a true
heap churns too much; decide by measurement.

### P+ — Anticipatory refinement (spend spare budget where the player is *about* to look)

Once the visible frontier is fully refined — every on-screen cell already below
`eps_px`, so the error heap is drained — the per-frame budget would otherwise sit
idle. Instead, **keep spending it on geometry the player can't see yet**, ordered
by *predicted* visibility:

- **Behind the near clip / off the frustum edges** — cells just outside the view,
  weighted toward the **facing direction** (turn anticipation) and the **movement
  vector** (travel anticipation). Turning or walking then reveals
  already-refined terrain instead of a coarse bloom catching up.
- The priority key generalises P's `we·proj/dist` to a **predicted** error:
  evaluate the screen-error as if the camera had rotated toward its recent angular
  velocity / translated along its recent motion. Cells the player is turning
  toward or walking into score highest; cells behind score lowest.
- It degrades gracefully: with no spare budget, nothing off-screen refines (P
  handles the visible set first); with ample budget, the resident set is detailed
  in a halo around the likely next view. This is the natural use for the
  "effectively free future hardware" headroom — turn surplus into latency hiding.

Composes on C+P: same worklist/heap, just an extended key and an off-screen
candidate set fed in once the on-screen set is drained. Bounded by the resident
window (and by M below, by RAM / the page cache).

## M — Retain everything; spill to a memory-mapped file

The thesis (`docs/MANIFESTO.md`, [[no-half-measures]]): hardware is effectively
free, so **don't throw out anything reusable.** Today a re-root or a window
eviction discards built cells; a far edit rebuilds from scratch. The endgame is
the opposite — **bake the whole visited world once and keep it:**

- The retained octree (cells + QEFs + 3a solve caches) and the EditStore are the
  durable bake. As the player roams, the resident set only grows; nothing already
  sampled is re-sampled.
- **When RAM fills, switch the backing store to a memory-mapped file** and let the
  kernel's page cache manage residency — hot cells stay in RAM, cold ones page to
  disk, transparently. The octree's flat cell array (`LocalVector<Cell>`, index-
  addressed, no pointers between cells) is already mmap-friendly: it is a single
  contiguous arena, so backing it with `mmap` is a allocator swap, not a
  rewrite. (The EditStore's node array is the same shape.)
- This dissolves the window/eviction model: the "window" becomes just *what's hot
  in the page cache*, not a hard residency bound. A re-root stops being a full
  rebuild — the cells already exist, mapped; the camera just walks into them.

**Sequencing:** M is a *memory-management* change under everything else, not a
prerequisite for E/C/P. Build E/C/P against the in-RAM `LocalVector` first; swap
the arena to an mmap-backed allocator when the resident set actually exceeds RAM
(it does not yet — a 128 GB machine holds a very large bake). Recorded now so the
data structures stay arena-shaped (no inter-cell pointers — already true) and the
retention model is designed *toward* keep-everything, not away from it.

**Caveat (honest):** the durable on-disk format then becomes a compatibility
surface — a changed `Cell` layout invalidates the mapped file. Version the arena
header; treat a mismatch as "re-bake from the EditStore + generator" (both are the
real source of truth; the octree is a cache). So M is safe to defer: nothing about
keeping the cache in RAM today forecloses paging it to disk later.

## 3b — Persistent buffer + partial GPU update (the last floor)

After 3a/E/C/P, the remaining O(window) work each grow is **not** solves — it is:
the serial slot-assignment scan, the per-leaf edge re-emit, the array assembly,
and the **full vertex-buffer re-upload** to the GPU (the render swaps the whole
`ArrayMesh`). 3b removes it:

- **Stable per-leaf vertex slots.** Today a leaf's slot is its rank in cell-index
  order, recomputed every frame. Replace with a slot **allocator**: a leaf keeps
  its slot across grows; freed leaves return slots to a free-list. Unchanged
  leaves' vertex data never moves.
- **Partial surface update.** Push only changed sub-ranges via
  `RenderingServer.mesh_surface_update_vertex_region` (or a `RenderingDevice`
  buffer) instead of rebuilding the `ArrayMesh`. The render-path change.

**Why measure-gated:** this changes `grow_world`'s output contract from "a full
array" to "a partial update" and adds a slot allocator — real complexity and real
risk. It is worth it **only if** the O(window) assembly + upload floor still
dominates after 3a removed the solves. Profile first (the perf overlay's grow
mesh-lag is the sensor); commit to 3b only against a measured floor.

**Contract note:** stable slots change grow's output *order*. The grow gate tests
are surface-signature based (order-independent), so they still hold; the byte-
identical `remesh` test is a *separate* entry point (collision) that keeps the
current full-emit path. Don't route `remesh` through the persistent buffer.

## I — Incremental grow (O(changed), not O(tree))

### The problem (measured, 2026-06-20)

With the controller driving eps to the floor (max detail until the GPU complains),
the retained tree reaches **millions of leaves**. Each grow still does O(tree) work
**serially** even though only the handful of cells it just refined changed:
`reconcile` re-collects every candidate, `reset_leaves` + `collapse_pass` re-walk
every cell, only the emit passes are parallel. Result: one core pegged, the rest
idle, and the refine queue (perf overlay) climbing to ~2M and barely draining — the
per-grow overhead dwarfs the budgeted refinement slice. The fix is to make a grow
cost O(*changed*), not O(*tree*). Three increments, gated by the existing invariants.

### Key decision: the frontier queue is keyed by `we`, not on-screen size

P scored refine candidates by **on-screen size** (`size·proj/dist`) — camera-
relative, so *every* key changes when the camera moves, and no persistent ordering
survives a move. So the persistent frontier is keyed by the cell's **geometric error
`we`** (the QEF residual — camera-independent). Refine order becomes "worst *error*
first" instead of "worst *on-screen* first": a sound, stable proxy that survives
moves intact. The screen-relevance lives in the eps controller and the error-vs-eps
collapse, not in the refine key. (Robert's call, 2026-06-20.)

### c1 — Persistent frontier queue (kill the re-discovery)

Maintain the refine-candidate set **incrementally** instead of having `reconcile`
re-collect it every grow. A cell enters the frontier when it becomes a refinable
coarse leaf (in-window, `want_leaf` false, no children); it leaves when refined
(gains children), evicted, or coarsened. Structure: an **indexed binary heap** keyed
by `we` (a heap + `cell → heap-pos` map for O(log n) delete/decrease-key), or a
`std::set<(we, idx)>` red-black tree if the constants don't matter. `refine_selected`
pops the worst-`we` cells until the µs budget; the rest stay queued (no re-walk, no
re-sort). Removes `reconcile`'s O(tree) collect for stationary refine.

### c2 — Incremental collapse (scope to the dirty set)

At a fixed eps + camera, only the cells whose QEF changed this grow (the refined
ones + their ancestors — already tracked by the `dirty` flag `reaccumulate`
propagates) can flip their collapse decision; the rest are identical. So re-run
`collapse_test` only over the dirty set instead of the global `collapse_pass`. An
eps *step* (controller) or a camera *move* still changes decisions tree-wide → fall
back to a full (or band-scoped) re-collapse on those frames, which are rarer than the
fixed-eps drain grows.

### c3 — Incremental emit — SUPERSEDED by measurement (2026-06-20)

The plan was to cache per-leaf triangles + stable slots and re-emit only the changed
band (the doc's "hard one"). A `dcthreads` probe (threads=1 vs 8 on a ~62K-cell drain)
**killed that plan before building it**: pass2 (`emit_leaf_edges`/`find_leaf`, the bulk
of the emit) was *already parallel* (8.8 → 4.0 ms), so the cache would optimize work
already spread across cores. The real serial bottleneck was elsewhere — pass1's
vertex-**collection scan** (5.0 ms flat across thread counts; `place_vertex` is cached
on a drain so the scattered per-cell read dominates) and `reset_leaves`.

So c3 became: **parallelize the serial scans** (reset_leaves + the pass1/pass2 mark→
prefix-sum→fill compactions), gated by the existing `parallel==serial` byte-identical
test. Drain recollapse 12.4 → 9.4 ms; pass1 now scales (5.0@1 → 1.9@8). With c1/c2 the
full drain grow is ~16.6 ms, down from ~32. The cache/stable-slot/partial-GPU-upload
rewrite (3b) is **not** worth its risk against the measured floor — shelved, not built.
Lesson: measure the serial-vs-parallel split before optimizing; the obvious target
(the expensive emit) was already handled.

### Gates

`grow==fresh`, `drain==full`, `parallel==serial` all still hold (incremental changes
*when/how cheaply* a cell refines, never the settled surface). Add the c-analogue of
`build_samples`: a **stationary refine grow touches O(changed) cells, not O(tree)** —
assert the per-grow collapse/emit work is proportional to the refined count, not the
resident count (the proof the re-walk is actually gone).

## Build sequence & cut line

1. **E — incremental edits — build first.** Biggest perceived-lag win, the most
   direct payoff from 3a (reuses the dirty-set), removes the single worst spike.
   **Implemented; pending the structural fix above** before it can ship.
2. **C — continuous budgeted refinement.** A controller + worklist change; turns
   the eps-step spikes into a bounded per-frame bloom.
3. **P — priority-by-error**, then **P+ — anticipatory refinement.** A heap on the
   existing error metric (P), then an extended predicted-visibility key feeding
   off-screen candidates once the visible set is drained (P+).
4. **3b — persistent buffer.** Only after measuring the post-3a/E/C/P floor.
5. **M — retain-everything / mmap spill.** A memory-management swap under the
   rest; build on the in-RAM arena, page to disk only when the resident set
   exceeds RAM. Keep the cell arena pointer-free so the swap stays an allocator
   change.
6. **Re-root incremental — deferred.** The root snap shifts the whole lattice
   frame, so every cell "moves" — the doc-13-B3 problem, now in the world-octree.
   Rare (only on leaving the root box). M largely dissolves it (the cells already
   exist, mapped). Recorded, not scheduled.

## Risks & gates

- **The one place bugs hide (E):** a `field_dirty` leaf that *isn't* re-sampled
  (stale field) or a newly-added surface pruned away by a stale accel. The gate is
  `grow-after-edit == fresh build` on the faithful field, plus the `build_samples ≈
  edit box` assertion. Veterans: [[validate-on-faithful-field]],
  [[dc-sdf-not-unit-distance]], [[edit-remesh-padding-gap]].
- **Determinism:** E and C/P must keep `grow==fresh` (surface-equal). The budget/
  priority only changes *when* a cell refines, never the *final* settled surface —
  a fully-drained worklist must equal a fresh build at that eps. Assert the
  drained state, not just intermediate frames.
- **Memory (3a, shipped):** the per-cell caches ~double `Cell` size. Accepted
  under the frame-time-over-memory steer ([[frame-time-budget]]); if the retained
  cell count makes it bite, move the caches to a side-array touched only in grow.
