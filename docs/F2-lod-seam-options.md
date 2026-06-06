# F2 — DC LOD-seam options (scratch decision doc, NOT committed)

A map of the problem and the realistic ways forward, so you can pick a direction.
This is a working note — move/commit/delete as you like.

---

## 1. The problem in one paragraph

The terrain renders at multiple levels of detail (LOD): near the camera, blocks
are meshed at full resolution; far away, at half / quarter / … resolution. Where
a fine block sits next to a coarse block, their surfaces don't line up, leaving a
**crack** you can see through. Fixing that join is "F2."

## 2. Why it's specifically hard for *our* mesher

Two facts collide:

- **Dual Contouring places one vertex per cell, anywhere inside the cell** (the
  QEF picks the spot). That's what gives us sharp features and clean surfaces —
  but it means a fine block and a coarse block of the *same* terrain put their
  boundary vertices in **different places**. They don't align, so they crack.
  (Transvoxel/marching-cubes put vertices *on grid edges*, which are shared by
  construction — that's why Transvoxel's LOD "just works" and ours doesn't.)

- **godot_voxel's transition system is per-side.** Each block can show a
  "transition surface" on each of its 6 faces independently, turned on only for
  the faces that border a coarser neighbour (`transition_mask`). This is built
  for Transvoxel's per-side transition cells.

So the engine wants a **per-face** answer, but DC's natural seam description is a
**3D boundary loop**, and — the thing I verified today — **those loops span
multiple faces**. A tilted plane through a block produces a *single* loop that
touches four faces at once. A per-side band can't be cleanly carved out of a loop
that wraps around the block, and where two adjacent faces are at different LODs
(cube edges/corners) you get gaps that need real transition-cell machinery.

## 3. What we went through to learn this

1. **Holes fix (done, shipped).** The "missing triangles" turned out to be
   back-facing triangles (coarse-gradient winding + non-planar quads + a QEF
   escaping its cell). Fixed; the core DC is watertight. *This was the big win.*
2. **F2 reproduction (done).** A fine block + coarse block of one sphere cracks:
   64 boundary edges. Established the test harness.
3. **Band algorithm (done, prototype).** `dc_seam.gd`: extract a mesh's open
   boundary loops, zipper a fine loop to a coarse loop into an additive band.
   On the sphere it drives 64 → 0. *Looked like success.*
4. **Padding pinned (done).** The fine block must recompute the coarse neighbour
   from its own padding; it needs a 2-coarse-cell slab → `MIN/MAX padding = 7`
   (up from 2/3) → **~3× buffer memory**. You accepted this as "make it work."
5. **The catch (today).** Before writing the C++ port I checked whether real
   terrain loops behave like the sphere's. **They don't** — terrain loops span
   faces (verified). So the per-side band the prototype proved doesn't fit real
   terrain through godot_voxel's per-side model. The sphere was a lucky-simple
   case. Better to find this in a 5-minute test than after a 250-line port.

**Net:** the algorithmic building blocks (loop extraction, zipper) are sound and
committed, but "per-face band via `transition_surfaces`" is not a viable *whole*
solution for terrain.

## 4. The options

Ordered roughly cheap → expensive.

### A. Pause F2 — accept the cracks for now
- **Do:** nothing. LOD-boundary cracks stay (visible at distance when panning).
- **For:** zero effort. These are *visual polish*, not a correctness/data bug
  like the holes or save/load were. Only show at distance; you said earlier they
  weren't your immediate concern. Frees us for higher-value work.
- **Against:** terrain isn't "finished"; the cracks are real and you've seen them.

### B. Seam pass (Gildea-style) — the correct fix
- **Do:** after per-block meshing, a separate pass meshes the *transition region*
  between two different-LOD blocks as **one piece**, with access to **both
  blocks' data**. No per-side decomposition, so faces/edges/corners all fall out
  naturally. This is what the DC literature (Nick Gildea, Miguel Cepero) actually
  does.
- **For:** correct and general; the "right" answer; no padding blow-up (you only
  pay at actual seams, not on every block).
- **Against:** it doesn't fit godot_voxel's per-block `VoxelMesher` API at all —
  the mesher never sees neighbours. Needs engine-level integration: hook into the
  LOD update where neighbour relationships are known, fetch adjacent block data,
  mesh the seam, and manage that extra geometry's lifetime. Likely a **patch to
  the vendored godot_voxel** (against our "don't edit the clone" policy) or a
  custom terrain subclass. Biggest effort + integration risk; hard to unit-test
  (needs the live pipeline).

### C. Per-side transition cells (Transvoxel-analogue for DC)
- **Do:** reinvent Transvoxel's per-side transition construction for DC — each
  side builds a transition from a half-resolution sampling of that face, with
  tables for the edge/corner cases.
- **For:** fits the engine's per-side model; no restructure.
- **Against:** this *is* the gnarly, table-driven part Transvoxel's author spent
  serious effort on, and DC's off-grid vertices make it harder, not easier.
  Effectively **research-grade**. Highest effort of the lot for a DC-specific
  reinvention; the edge/corner cases are the whole difficulty.

### D. Partial per-side band — pragmatic, imperfect
- **Do:** extend the prototype — split each loop at face boundaries, band only
  the coarse-bordering sides.
- **For:** moderate effort; reuses what's built; would fix most *mid-face* cracks.
- **Against:** leaves residual gaps at cube **edges/corners** (where adjacent
  sides differ in LOD); loop-splitting + endpoint-matching is fiddly; still
  carries the ~3× padding cost. You'd trade big cracks for little ones.

### E. LOD-distance tuning — band-aid
- **Do:** push `lod_distance` out so LOD boundaries sit far from the camera.
- **For:** trivial (settings only); makes normal play look fine quickly.
- **Against:** not a fix — cracks still exist, just farther away; more
  high-detail blocks → more memory/perf; fundamentally at odds with planet-scale
  (LODs are mandatory there). A delay tactic.

### F. Skirts — the pragmatic hammer
- **Do:** each block emits a downward "skirt" wall around its boundary that hides
  the crack behind geometry.
- **For:** simple, robust, handles every case (faces/edges/corners), fits the
  per-block API (no neighbour data), cheap. **Most shipping voxel games use
  skirts.**
- **Against:** not watertight (overlapping/hidden walls), some overdraw, can show
  a faint lip at boundaries. You've philosophically rejected skirts (Cepero's
  "emancipation from the skirt") — but they're the honest pragmatic fallback if
  cracks start to bug you before a real fix is worth it.

### G. Hybrid mesher — Transvoxel far, DC near
- **Do:** Transvoxel (working LOD) for distant LODs; DC only at LOD0 where sharp
  features and edits matter.
- **For:** distant LOD "just works"; keep DC's quality up close.
- **Against:** two meshers; the LOD0↔LOD1 join becomes a DC↔Transvoxel seam (a
  *different* mixed-mesher seam problem); added complexity; partly undercuts the
  reason we migrated to DC at all.

## 5. The honest meta-point

LOD seams are DC's known Achilles heel — the price of off-grid vertices. We
migrated off Transvoxel (which had working LOD) for DC's surface quality and
sharp features. That trade was the right call for *close-up* terrain and editing;
the bill comes due exactly here, at LOD joins. None of the real fixes are cheap.

## 6. My recommendation

- **Now: A (Pause).** The cracks are polish, only at distance, and everything
  load-bearing (holes, save/load, edits) is solid. Ship the wins; don't sink the
  next several days into a hard problem that isn't hurting core play.
- **When F2 becomes worth it: B (Seam pass).** It's the correct, general answer
  and the one DC practitioners actually use; budget it as a real feature with
  engine integration, not a quick patch.
- **If cracks get annoying before B is worth it: F (Skirts)** as a deliberate,
  reversible stopgap — ugly in principle, effective in practice, and removable
  the day B lands. (E/LOD-tuning can buy a little time too, basically free.)
- **Avoid C and D** as primary plans: C is research-grade for a reinvention we
  don't need, and D buys an imperfect result for real effort.

The committed `dc_seam` building blocks aren't wasted — loop extraction and the
zipper are reusable inside a seam pass (B) when we get there.
