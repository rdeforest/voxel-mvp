# The Adaptive-Density Octree Substrate

*The design spec for the persistent, world-fixed adaptive-density octree that
becomes the world's data + render substrate. The conceptual ground (field + DC-QEF,
why an octree, parts-as-voxels) is [`03-dc-qef-geometry.md`](03-dc-qef-geometry.md);
the **mesher** migration (DC over godot_voxel data, the path-b render layer) was
[`../implementation/14-dc-qef-transition.md`](../implementation/14-dc-qef-transition.md)
and has largely shipped. This doc is the next architectural step: making the octree
itself the substrate.*

## TL;DR

Today the render is a Dual-Contouring octree **rebuilt every recenter from a
camera-snapped clipmap** of godot_voxel's fixed-1m-grid data. That clipmap is the
source of two coupled problems: LOD seams (a cell-**size** step between fine and
coarse data) and **view-dependence** (the same geometry meshes differently from
different camera positions — see [[dc-thin-feature-collapse-bug]]).

The fix is a **persistent, world-fixed adaptive-density octree**: one octree whose
cells are aligned to fixed world coordinates per level, refined where there's detail
(and near the camera), coarsened where there isn't, sourced from **fine field data**.
A coarse cell derives its vertex + normal from its children's **accumulated QEF**, so
it sits on the fine surface — seams dissolve. Because the grid is world-aligned, a
fixed feature always falls in the same cells regardless of where you stand, so the
meshing is stable; only the LOD *level* changes as you move, and that change is
geomorphed.

This is the **same substrate parts-as-voxels rides on** (imprint a part's shape into
the SDF + material channel; one field, one mesher, one integrity system). We build it
in two stages:

- **Phase A — render substrate over godot_voxel data.** The persistent world-fixed
  octree replaces the camera clipmap as the *render* layer; godot_voxel stays the
  data store underneath. Fixes seams + view-dependence; validatable today with the
  CSG tool ([[csg-validation-tool]]). Shippable on its own.
- **Phase B — data substrate; godot_voxel removal.** The octree *is* the store:
  adaptive storage, streaming, persistence, collision, and a write API replacing
  `VoxelTool`. Enables sub-meter / parts-as-voxels (Tier 2). Larger; A is its first
  stage.

Phase A is approved to go first; B follows in logical chunks.

## Why now

Three things make this the right moment:

1. **The render bugs are structural, not tunable.** The path-b work (geomorph,
   per-triangle winding, error-LOD collapse, hysteresis) fixed the *data step* and
   the *see-through winding*, but the residual **size step** and the
   **view-dependence** are inherent to a camera-snapped clipmap rebuilt per move.
   They don't yield to more tuning; they yield to a world-fixed persistent octree.
2. **The validation instrument exists.** The CSG tool stamps **exact analytic SDF**
   (box/cylinder/sphere) so we can audit the new mesher against a known field instead
   of guessing from procedural terrain. That loop is what makes a substrate rewrite
   tractable — every change is checkable.
3. **It unblocks the deferred vision.** Sub-meter parts, true wall-blending-into-
   rock, fracture along arbitrary surfaces — all wait on adaptive density. Doc 03
   already chose "start fat" (logs/blocks); the octree is what lets us later go thin.

## The diagnosis this fixes (from the 2026-06-07 session)

The thin-feature flapping ([[dc-thin-feature-collapse-bug]]) has **two independent
causes**, and the substrate must address both:

- **View-dependence (the clipmap).** `dc_terrain_manager` snaps the clipmap centre to
  a 32 m grid around the player and rebuilds the whole octree each recenter, so which
  cells straddle a thin feature changes as you move; plus error-collapse is keyed off
  camera distance with frame-to-frame hysteresis, making the mesh path-dependent. **A
  world-fixed octree removes this by construction** — cells don't shift under a fixed
  feature.
- **Collapse-metric averaging (independent — carries over unless fixed).** The
  error-collapse uses `we = sqrt(residual / count)` (`dc_octree_mesher.cpp`), dividing
  total squared residual by plane count. A few high-residual planes from a thin spire
  are *averaged away* by many flat-ground planes, so a coarse cell collapses over real
  detail and stitches a runaway vertex to fine neighbours → slivers. **This must be
  replaced as part of Phase A** (see "Decisions needed").

## Core design

### 1. World-fixed cell grid, camera-driven refinement

The octree's cells are aligned to **fixed world coordinates** at each level (a level-k
cell spans `[k·2^k, (k+1)·2^k)` in world units, not relative to the camera). What's
camera-dependent is only **which cells are refined**: fine near the viewpoint / near
surface detail, coarse far away. Result: a fixed feature always falls in the same
cells (stable meshing); moving the camera changes a cell's LOD *level*, never its
position, and that level change is geomorphed (the field is blended across the
boundary as `Clipmap::value()` already does). This is the single change that kills the
view-dependence.

### 2. Build to fine data, collapse with accumulated QEF

Unchanged in spirit from the shipped error-LOD work, made persistent:

- Sample the **finest available field** at the leaves (the data-resolution floor).
- Accumulate each cell's QEF up the tree (`Qef::add`, `nsum`) so a parent carries
  **all** the fine Hermite data within it — no coarse-corner undersampling.
- A coarse cell's vertex + normal come from its accumulated QEF, so it **sits on the
  fine surface**. Adjacent fine and coarse cells of the same field agree at the seam →
  cracks dissolve without a balance pass (point-location meshing stitches size jumps;
  [[dc-no-balance-pass]]).
- Collapse a node to one leaf when one vertex represents its accumulated data within a
  screen-error threshold — **but using a metric that does not average detail away**
  (Decisions needed).

### 3. One field, multiple channels, per leaf

Each leaf carries the field sample set the world needs: **SDF** (geometry) + **material
id** (the 8-bit channel shipped in [[csg-validation-tool]]) + room for future channels
(temperature, density, …) at possibly-coarser resolution ([`06-channel-architecture.md`](06-channel-architecture.md)).
Roles ("this is a wall") stay in **sidecar indexes**, never in the leaf. The material
sampling the DC mesher already does (emit per-vertex colour, id 0 = natural) ports
directly.

### 4. Persistent + incremental

The octree lives across frames (Phase A's persistence builds on the shipped collapse-
hysteresis state, which is already a world-keyed `HashSet`). Edits dirty a bounded
region; only affected nodes re-mesh (retiring the whole-clipmap ~62 ms rebuild). Camera
movement refines/coarsens at the margins, not a full rebuild.

## Finding (2026-06-07): the cells are already world-aligned

Tracing the live code while starting A1: `dc_terrain_manager` snaps the clipmap
centre to `_COARSEST_CELL` (32 m) and `root_origin` is always a multiple of 32, so
every leaf (size ≤ 32) already sits on a world-aligned grid. A fixed feature does
**not** shift cells as you move — the "world-fixed cell grid" half of A1 is, in
effect, already true. What actually causes the view-dependence is narrower:

1. **Discrete LOD bands.** Data resolution drops with distance-from-camera (LOD0
   only within ~16 m; ~8 m data by ~200 m), and the band boundaries snap in 32 m
   steps, so a feature pops as you cross one. A structure far out is genuinely
   meshed from downsampled data.
2. **Flapping specifically** = the collapse-metric averaging bug (now fixed, A3) +
   LOD size-step seams (geomorph + per-triangle winding already mitigate).
3. **Hard limit:** fine data far out is memory-bound (LOD0 over a 200 m radius ≈
   256 MB). Distant structures stay coarse — that's normal LOD. The goal is
   *clean-coarse*, not *flapping-coarse*.

**So A1 is reframed.** Rather than "world-fix the grid" (done), the substantive work
is: (a) make error-driven collapse the **default LOD mechanism** so coarse cells
derive from accumulated *fine* QEF and sit on the fine surface — done now that A3
made collapse safe (`error_driven` default ON); (b) the genuinely-remaining decision
is the **fine-data budget** (A2) — how far out fine data extends, a memory/perf
tradeoff that sets how far structures stay crisp; (c) persistent store + incremental
remesh (A4) is now a *perf* optimisation (retire the 8 m-recenter full rebuild), not
the visual fix. B is unchanged.

## Correction (2026-06-08): the honest field is Phase B, not a Phase A bolt-on

Two sessions of work + a self-inflicted bug forced a sharper read of where the
view-dependence actually lives and what can fix it. **The 2026-06-07 finding above
was half-right** — error-collapse from accumulated QEF *does* make coarse cells sit on
the fine surface, but **only where there is fine data to accumulate.** Within the fine
core (LOD0, now ±64 m after `LEVEL_DIM` 65→129) that holds. Beyond it the leaves are
built from **godot_voxel's lossy downsampled mips** (the clipmap's coarse levels), and
**geomorph blends those lossy levels by camera distance.** That blend — not the cell
grid (world-aligned, fine) — is the remaining view-dependence and the LOD seam: the far
field is meshed from data that (a) is lossy and (b) blends differently as you move.

**This is not fixable in Phase A.** godot_voxel only streams LOD0 near the camera; far
regions are coarse by construction, and fine data over a large radius is memory-bound
(the doc's hard limit). So as long as the data source is godot_voxel's mip clipmap, the
far field stays coarse-and-blended and geomorph (or a visible step) is unavoidable.
**Retiring geomorph requires fine data everywhere, which is Phase B** — the octree as
store, *defer-to-generator*: the generator is a fine field at every point, edits ride in
the sparse store, so coarse cells accumulate from genuinely-fine QEF — no mips, no blend,
faithful at every level, identical from every vantage. **That is where geomorph dies**,
and it dies as a *consequence of an honest field*, not as a standalone deletion (deleting
it over the lossy mips just exposes the step — a regression, manifesto #8 / Hytale).

**Cautionary tale — the surface-sparse prune (commit da8a988, reverted 34ef2dd).** Built
to cut the ~5 s movement re-mesh (profiled: 4 s of it is `accumulate` over 10.8 M cells,
mostly empty), a build-time prune skipped provably-empty regions and ran **16× faster
with byte-identical output** — *on a raw `y − surface` field*. On the **faithful** field
(real generator through godot_voxel's lossy SDF encoding + the geomorph blend) it deleted
**~45 % of the surface** and spawned big spanning slivers, caught live by `dcaudit`. The
prune trusts a local gradient; the lossy-mip + geomorph field distorts that gradient.
**Lessons:** (1) validate mesher changes on the faithful encoded multi-level field, never
a raw analytic one ([[validate-on-faithful-field]]); (2) the prune is a *Phase B*
mechanism — only safe once the field is faithful at every level, which is exactly what
fine-data-everywhere buys; bolting it onto Phase A's mips is the bug; (3) per
**non-negotiable #8**, that 5 s is **worker-thread wall-clock that never touches
framerate** — the "second kind" of cost the manifesto says to *leave alone*. It is now
the cautionary tale on manifesto line 182. The field-model rework is justified by
**view-dependence and the lying-mip seam (correctness)**, with any speedup a byproduct —
never the reason.

**Net reframing of the remaining work:** Phase A's *near* field is at its ceiling (A1/A3
done; A4 done for edits via the incremental splice — commit afd1c0a). The substantive
substrate work that remains is **Phase B's store-over-generator faithful field**, where
geomorph, view-dependence, and affordable surface-sparse meshing all resolve together.
Don't spend more effort making the godot_voxel-mip far field "honest"; spend it replacing
the data source. (The dense build is correct and ships; the 5 s is left as-is per #8.)

## Phase A — render substrate over godot_voxel data

**Goal:** the persistent world-fixed octree is the render layer; godot_voxel stays the
data store, streaming, LOD source, and collision owner. Fixes seams + view-dependence.
Shippable.

**Keep (unchanged):** godot_voxel storage / streaming / generator / SQLite persistence
/ per-block collision (`VoxelMesherDC` static body); the `DCRegionReader` fine-data
read path; the CSG/edit actions (still write via `VoxelTool`); the material channel.

**Build:**

- [ ] **A1 — World-fixed octree node store.** Replace the camera-snapped clipmap with
  a persistent octree keyed by world coordinates. Cells align to world grid per level;
  the resident set is bounded by view radius. Reuses the collapse-hysteresis HashSet
  shape.
- [ ] **A2 — Fine-data sourcing.** Feed leaves from `DCRegionReader` at the finest LOD
  available for each region (LOD0 near the camera, coarser data farther — but the
  *cell grid* stays world-fixed; data LOD is just the sampling floor). Edit-inclusive
  (the [[edits-first-class]] invariant) for SDF **and** material.
- [ ] **A3 — Collapse metric fix.** Replace `sqrt(residual/count)` with a metric that
  a single high-residual plane can veto (Decisions needed). Validate on a CSG-stamped
  spire: it must stay refined, not flap.
- [ ] **A4 — Incremental remesh.** Dirty-region re-mesh on `terrain_sdf_changed`
  (reuse the bus + dirty-queue discipline), refine/coarsen at the camera margin —
  retire the whole-clipmap rebuild.
- [ ] **A5 — Retire the clipmap.** Remove `dc_terrain_manager`'s camera-snap recenter
  once the persistent octree covers it; keep the worker-thread mesh + main-thread swap.
- [ ] **A6 — Validation pass.** CSG-stamp box/cylinder/sphere; confirm the mesh hugs
  the analytic surface, is watertight + crack-free across LOD, and is **stable under
  camera motion** (the bug's acceptance test). `dcaudit` suspect-triangle count drops.

**Acceptance:** a stamped sphere meshes identically from any vantage; no flapping
slivers on a thin stamped spire; LOD transitions seam-free; edit re-mesh is incremental.

## Phase B — data substrate (godot_voxel removal)

**Goal:** the octree *is* the store. Enables sub-meter / parts-as-voxels (Tier 2).
Each bite is independently shippable; godot_voxel can't fully go until collision +
persistence move.

**Build (sketch — designed in detail when A lands):**

- [ ] **B1 — Adaptive octree storage.** Sparse, surface-dominated node store (the
  memory budget in doc 03: store *surface area*, not volume). Per-leaf SDF + material
  (+ Hermite point/normal if crisp creases need it — Bite E from doc 14).
- [ ] **B2 — Write API replacing `VoxelTool`.** The edit verbs (dig/fill/flatten/CSG)
  imprint into the octree directly (subdivide-on-imprint where a fine brush lands).
  This is the wide ripple across `scripts/actions/` — design the API so actions change
  in one place.
- [ ] **B3 — Streaming + persistence.** Stream the octree (resident = players × view
  radius); persist edited nodes (the op-log direction in
  [`05-network-architecture.md`](05-network-architecture.md) eventually replaces
  `VoxelStream`).
- [ ] **B4 — Collision from our mesh.** Drive collision off the octree mesh
  (`ConcavePolygonShape3D` per region, regenerated on edit) — the deferred
  "single-mesher consolidation." **Prerequisite for removing godot_voxel.**
- [ ] **B5 — Parts-as-voxels (Tier 2).** Imprint sub-meter / rotated parts into the
  field with local subdivision; one integrity system over the unified field.
- [ ] **B6 — Remove godot_voxel.** Once B1–B4 cover storage/stream/persist/collision.

## Decisions needed (before / during A)

1. **Collapse metric (A3) — the one real algorithmic choice.** Options, recommend
   first:
   - **Max/peak per-plane residual** — collapse only if *every* plane is fit within
     eps. A single high-residual plane (the spire) vetoes. Simplest; directly fixes
     the averaging.
   - **Normal-cone veto** — refuse collapse if the accumulated normals span more than
     a threshold cone (a flat region has tight normals; a spire-through-ground cell
     does not). Robust to noise; a touch more state.
   - Combination. *Recommendation: max-residual first, add the cone if needed; the CSG
     spire is the test.*
2. **Fine-data sourcing — SETTLED (2026-06-08), see Correction above.** godot_voxel LOD0
   only covers near the camera; far regions only have coarse mips. The earlier hope —
   "geomorph blends it, no seam" — was wrong: geomorph blending those lossy mips by camera
   distance *is* the residual view-dependence + seam, and it can't be removed while the
   data source is godot_voxel (fine-everywhere is memory-bound). The honest fix (fine field
   everywhere, accumulate fine QEF, no geomorph) is **Phase B's store-over-generator**, not
   Phase A. Far field stays clean-coarse in A; faithful in B.
3. **Resident-set bound + eviction.** How far the persistent octree extends and how it
   evicts (Phase A bounds it to view radius; Phase B streams).
4. **Storage format (B1).** Node layout, compression policy (surface-dominated),
   Hermite-or-not. Deferred to B design.
5. **Persistence format (B3).** Edited-node serialization vs op-log. Deferred to B.

## What we keep from godot_voxel, and for how long

| Layer | Phase A | Phase B |
|-------|---------|---------|
| Storage (`VoxelData`) | keep | replace (B1) |
| Streaming / generator | keep | replace (B3) |
| SQLite persistence | keep | replace (B3) |
| LOD source | keep (data floor only) | gone (octree is LOD) |
| Collision (`VoxelMesherDC` body) | keep | replace (B4) |
| Render | **ours (octree)** | ours |
| Edit API (`VoxelTool`) | keep | replace (B2) |

## Costs / risks

- **Phase A is medium-large but reversible-ish** — it swaps the render layer; the
  fallback (`dcmanager`/`dcsolo` → godot_voxel render) stays until A is trusted.
- **The collapse metric is the only fiddly algorithm**; everything else is bookkeeping
  (a world-fixed octree is *simpler* than a re-snapped clipmap).
- **Phase B's write-API ripple** touches every edit verb — design B2 so actions change
  once, and lean on the CSG tool to validate each verb against a known field.
- **Crisp creases** still need Hermite storage (doc 14 Bite E) — defer until built
  structures read too soft; terrain + fat parts are fine on field-gradient normals.

## When this lands

- A's mechanism rationale graduates into `../../architecture.md`; decisions into
  [`02-architectural-commitments.md`](02-architectural-commitments.md).
- This chapter stays as the substrate spec (B continues against it). Doc 14 remains
  the historical record of the mesher transition that preceded it.
