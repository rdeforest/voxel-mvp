# DC-QEF Geometry: The Field-Based Representation

*The spec, not the migration. For the one-shot transition work plan, see
[`../implementation/14-dc-qef-transition.md`](../implementation/14-dc-qef-transition.md).*

## TL;DR

The world is a **continuous signed-distance field** (plus material and
other channels) sampled on an octree lattice and meshed for display
using **Dual Contouring with Quadratic Error Functions (DC-QEF)**. There
is no separate "voxel" data type and no separate "part" data type. The
field is the world; the mesh is just what you draw to show it.

This is the representation Miguel Cepero (Voxel Farm) demonstrated over
a decade ago on his Procedural World blog. Games still don't ship this
because the meshing math is harder than Marching Cubes and the storage
discipline takes some learning. Both are tractable.

## The core realizations

### 1. A voxel is not a cube of matter — it's a sample of a field

The mental model that unlocks everything: a voxel is a **sample point**
(a grid corner) carrying a field value — signed distance, plus optionally
material and surface attributes. The *surface* doesn't live "in" a
voxel; it lives *between* samples, wherever the field crosses zero along
an edge.

- Cepero's own words: "you need 8 voxels to make a single cube ... there
  is no way to produce anything visual with just one voxel." A volume is
  bounded by its 8 corner samples. One sample is just a number at a
  point.
- The pixel/voxel disanalogy that trips everyone up: a **pixel IS the
  colored square** (value == area). A **field-sample voxel is a probe of
  a continuous function** (the "stuff" lives between samples). Minecraft
  uses the pixel model. We use the sampling model.
- Consequence: the example "rock" in Cepero's posts was never one voxel
  — it's a contoured isosurface threaded through a whole neighborhood
  of samples.

> **Naming note:** "voxel" carries cube baggage we're shedding. Candidate
> replacements floated: *field sample*, *node*, *corner sample*,
> *Hermite sample* (the DC variant stores point+normal). Decision
> deferred until the data model has been felt in code — the right name
> usually falls out of how we end up talking about it.

### 2. The grid is decoupled from the field; the voxel values ARE the field, sampled

- The **field (SDF)** is the continuous, abstract shape — defined
  everywhere.
- The **grid** is just a sampling lattice — *where* we probe.
  Bookkeeping, not geometry. This is exactly why Cepero could swap a
  regular grid for an adaptive octree and run the *same* DC unchanged:
  he changed where he samples, not what he samples.
- A **voxel value** is one stored sample. The voxels are a
  discretization of the field, not independent objects.
- So: the field's shape is independent of grid resolution/layout
  (resample the same rock finer → better mesh from the same field). But
  the stored samples *are* our representation of the field once we
  commit to a grid. (We may keep an analytic SDF for procedural content
  and sample on demand — but for player-edited content, the stored
  samples are the truth.)

### 3. "Irregular voxel shapes" = irregular SURFACE, regular CELLS

Crucial clarification to avoid a wrong turn:

- The **grid cells stay cubes** (axis-aligned, regular or octree-
  subdivided).
- What's irregular is the **surface threaded through them**, because the
  surface position inside each cell is set by the field values + QEF,
  not snapped to cell geometry. The vertex can sit anywhere inside the
  cell.
- "Off-grid" means **the surface is off the grid**, NOT that cells are
  weird shapes. Arbitrary angles and curves come out of a perfectly
  regular cubic lattice.

This is the resolution of the part/terrain unease: there was never a
real reason for the exception. The dichotomy was an artifact of "voxel
= cube of matter." Field + DC erases the need for a separate mesh-based
"part" system.

### 4. Imprinting, not CSG (how arbitrary shapes get INTO the field)

Cepero does not keep a CSG tree. Placing a column/rock/arch **imprints**
its shape into the field like painting into a bitmap, then **throws
away the source object's identity** — only the modified field remains
(MS-Paint-drawing-a-circle analogy: afterward only pixels remain, not
the circle).

Consequences: any closed 3D geometry can be a brush; subtract as well as
add (overhangs/arches free); brushes carry arbitrary rotation (off-grid
content); physics can later fracture along *different* lines than how
it was assembled.

---

## What Dual Contouring is (and why it, specifically)

Both Marching Cubes (MC) and DC extract the zero-isosurface of a scalar
field sampled on a grid. The difference is **where the vertex is
allowed to go**:

- **MC** pins vertices to grid *edges* (interpolated along an edge where
  sign changes). It physically cannot represent a sharp corner living
  *inside* a cell → everything comes out rounded/melted. Cepero
  rejected it for this.
- **DC** places **exactly one vertex per cell**, and that vertex can sit
  *anywhere inside* the cell — including precisely on a crease.

DC algorithm:
1. **Find crossings** — for each grid edge with endpoints of opposite
   sign, the surface crosses it; find the zero point.
2. **Get a normal at each crossing** — the gradient ∇f (a few extra
   field samples, or analytic). Point + normal = **Hermite data**. MC
   throws normals away; that's exactly why it can't see corners.
3. **Solve for the cell vertex (QEF)** — a cell may have several crossed
   edges, each giving a tangent plane. Minimize the **Quadratic Error
   Function** = sum of squared distances from the point to all those
   planes. The minimizer lands on the crease where families of planes
   intersect. (Averaging instead of solving the QEF would smooth the
   corner away — the QEF *recovers* it.)
4. **Build quads** — each crossed edge is shared by 4 cells (in 3D);
   join those 4 cells' interior vertices into a quad. Stitch all quads
   → watertight mesh.

The elegant payoff Cepero kept stressing: **the same algorithm produces
both razor edges and smooth organic curves with zero mode-switching.**
Sharp if the field has a crease, smooth if it doesn't. The geometry's
character lives in the field; the mesher is neutral. *This* is what
lets terrain and architecture be one fabric.

Implementation cautions to file away:
- **QEF can misbehave** when planes are near-parallel (flat regions):
  the system is ill-conditioned and the minimizer can fly outside the
  cell. Standard fix: pseudo-inverse / SVD with small singular values
  clamped, plus clamp the result to cell bounds. This is the single
  fiddliest part of a DC implementation.
- **Vanilla DC can produce non-manifold vertices** where thin features
  pinch a cell. **Manifold Dual Contouring** (Schaefer et al.) allows
  multiple vertices per cell when the surface passes through as
  topologically separate sheets. Know the term before hitting the bug.
- **Pairs naturally with an octree** (one vertex per cell → adaptive
  cell sizes; QEFs can be combined up the tree for LOD simplification).

---

## DC-QEF is a MESHING step only — zero bearing on physics

DC-QEF is the SDF→triangles **presentation** path. Physics never reads
its output. But the SDF itself is *great* for physics (just not via the
mesh):

- **Collision / penetration:** field value = signed distance to surface;
  negative = penetration depth. ∇f = contact normal. Query the field,
  no mesh.
- **Volume / mass / buoyancy:** integrate the field over a region (sum
  inside-samples × cell volume). Embarrassingly parallel.
- **Substrate quantities** (temperature, pressure, momentum) are *also*
  fields on the same lattice — the SDF is one field among several.
  Local cell↔neighbor interaction → O(N).

Clean separation:
- **Simulation/state layer:** the SDF + physical-quantity fields.
  Physics reads/writes locally, per cell.
- **Presentation layer:** DC-QEF, runs over the SDF only when we need
  to draw. Re-mesh at a different cadence than we simulate; mesh only
  visible chunks; skip meshing on a headless server. None of it touches
  correctness.

Caveat: rigid-body physics on a fractured-off chunk DOES need geometry
(a mesh or convex decomposition) — DC re-enters there, but as a physics
*input* generated from the field, not as the field itself.
Continuum/substrate physics stays entirely in field-space and never
meshes for simulation.

This separation maps onto what we already shipped: collapse
materialization (`architecture.md` → Materialization) already greedy-
merges a voxel set into boxes for a `RigidBody3D`. Under DC that
"extract geometry for the rigid-body solver" step is the same idea,
generalized from boxes to a contoured mesh / convex decomposition.

---

## Limits on the geometry (what the field can/can't represent)

Two limits:

1. **Feature size / separation (≈ Nyquist).** Can't resolve a field
   feature thinner than ~2 sample spacings, regardless of which side is
   "solid." With 0.3 m voxels, features ≥ ~0.6 m. A thin slab between
   sample rows vanishes; a slot thinner than the spacing closes up.
   **Governed by grid spacing.**
2. **Sharpness fidelity per cell (the one-vertex-per-cell rule).** A
   single cell holding *two* distinct sharp features forces its lone QEF
   vertex to compromise → artifacts / pinching. NOT fixed by finer grid
   globally — fixed by Manifold DC or local subdivision so each feature
   gets its own cell. A single 90° corner is fine (one feature, one
   vertex).

**Adaptive density (octree)** — the graceful resolution-increase
technique: subdivide cells near surface detail, leave flat/empty
regions coarse. Because the octree preserves grid *topology* (cells
still cubes), **the same DC-QEF runs unchanged.** Two gotchas (both
from Cepero's posts):
- On a shared edge between a large and small cell, contour only the
  *small* edge, or you get cracks.
- Second pass to keep neighbors within one subdivision level apart
  ("restricted"/"balanced" octree) → concentric rings of cell size away
  from detail. Skip it → T-junction seams.

**Concrete "2×4" finding:** a nominal 2×4 is really 38 mm × 89 mm; the
38 mm axis is binding. At building-scale voxels (0.3 m) lumber is
*invisible* — an ~8× scale gap. To support lumber you need a fine base
grid (~5–10 mm) **or** local octree subdivision wherever a fine brush
is imprinted. Watch two stress points: **board ends** (two corners ~38
mm apart can share a cell → limit #2) and **off-axis placement**
(rotated flat faces cut diagonally across cells → needs finer spacing
than the axis-aligned case).

**Design decision taken: don't hand players anything as thin as a 2×4
to start. Begin with logs and stone blocks (Valheim-style) — fat
features relative to the build grid — and see how it feels before
paying for fine lumber.**

(Note: current v0.0/v0.1 already ran into the dual of this — "sub-cell
parts can't be represented at 1m voxel resolution," the deferred SDF-
seam-matching item in STATUS.md. DC + adaptive density is the
principled answer to that deferral.)

---

## Memory budget sanity check (the "hardware keeps improving" thesis)

Back-of-envelope for a 100 km² world (10×10 km footprint, ~1 km usable
height) at 5 mm finest detail:

- **Naive dense grid:** ~8×10¹⁷ samples ≈ **0.8 exabytes** at 1
  B/sample. Civilization-scale. Proves you must NEVER store the world
  densely.
- **Surface-only octree, sane policy** (terrain meshed ~0.5 m, 5 mm
  reserved for ~1000 build sites): **~1.5 TB total** — terrain a
  trivial ~10 GB, essentially all cost is fine build detail. Five-to-six
  orders of magnitude rescue the instant you store *surface area*, not
  volume.
- **Pessimistic** (5 mm everywhere on terrain): ~96 TB. Finite but
  pointless.

Takeaways: **memory is governed by how much fine-detail building you
allow, not world size** (world size is nearly free; build fidelity is
what you buy). These are *static-storage* numbers — stream the octree,
resident set = players × view radius (a few GB). A 1.5 TB build-
detailed 100 km² world is trivially within a single 2026 NVMe drive;
the exabyte/terabyte gap *widening* with hardware is the project
premise, vindicated.

---

## Volumetrics (dust, vapor, cloud, fog) — captured for later

Smoke/fog are **not isosurfaces — do not mesh them.** "dirt↔smoke↔air"
is *one* surface (dirt↔air, meshed via DC) plus *one volume* (smoke
density in the air, ray-marched). Two representations on one grid:

- **Solids:** SDF → DC-QEF surface. Sharp, opaque, has a boundary.
- **Participating media:** a **density field** (0 = clear, high =
  thick), rendered by integrating light along the ray (absorption +
  scattering + emission; Beer-Lambert exponential transmittance). No
  mesh, ever. This density field is just another substrate channel the
  physics advects.

Compositing: render solids first (color + depth), then ray-march the
volume *up to that depth*; final pixel = in-scattered light + solid
color × transmittance. Practical notes: volume field can be **much
coarser** than the SDF (no sharp edges); empty-space skipping is
essential and free with the octree; self-shadowing (secondary light-
march) is the expensive part — ship without it first.

---

## The case FOR adopting this

- Kills the part/terrain dichotomy permanently — one representation,
  one mesher.
- One algorithm yields both crisp architecture and smooth terrain.
- Field model is the correct substrate for physics (collision, volume,
  mass) and for the substrate/emergent-behavior goals — geometry and
  physics share the lattice.
- Proven: Voxel Farm shipped this >10 years ago; mainstream games
  still haven't.
- Aligns with the long-term "own the whole stack" direction.

## The case AGAINST / costs

- A step away from godot-voxel's well-trodden blocky/Transvoxel path.
- LOD seam handling for DC is real work (see the transition chapter) —
  harder than for Transvoxel, which exists *specifically* to stitch
  LOD cracks.
- Sharp features need Hermite data (point+normal at crossings) stored,
  which godot-voxel's scalar-only storage doesn't natively do.
- QEF robustness (SVD clamping, cell-bound clamping) is fiddly.

## Decisions taken

- Adopt field + DC-QEF; retire the cube/part exception.
- **Skip mesh→voxel conversion entirely.** Only reason to have it was
  importing foreign mesh assets, which we don't want (licensing
  contamination). This also cleanly sidesteps Voxel Farm's voxelization
  **patents** (US 10,062,203 and US 11,847,738 — the flood-fill mesh→
  watertight-volume method). Reimplement from Cepero's *public blog* +
  *published academic papers* (Ju et al. DC/QEF; Lorensen & Cline MC)
  — clean-room. Do NOT decompile the old VF3 blob.
- Start build vocabulary fat (logs, stone blocks), not thin lumber.

> **Patent note:** A patent covers only what its *claims* recite.
> DC+QEF (Ju/Losasso/Schaefer/Warren 2002), Marching Cubes, isosurface
> extraction, SDF imprinting, octrees, GPU stream-compaction — all
> prior art, not Voxel Farm's to claim. The patents are narrow: a
> specific voxelization method we're not using. Not legal advice; a
> real FTO review is appropriate before shipping.
