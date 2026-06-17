# Worldgen research — volumetric & stratified terrain (2009–2024)

Lookup material for the worldgen direction. The *decision* this informs lives
in [`design/19-volumetric-worldgen.md`](../design/19-volumetric-worldgen.md);
the *work-order* in
[`implementation/planned/18-volumetric-worldgen.md`](../implementation/planned/18-volumetric-worldgen.md).
This doc is the verified literature survey behind both.

Sourced from a fan-out web survey (2026-06-17), each load-bearing claim
adversarially verified (3-vote, kill on 2/3 refute). Citations below survived
that pass unless marked otherwise.

## The one-sentence finding

The graphics literature splits into two camps that **do not overlap**:
representations that give true 3D volumetric geometry + stratified geology
(material stacks, implicit construction trees), and simulations that give
geomorphological *plausibility* (tectonic uplift + stream-power erosion) — and
every simulation in the second camp is heightfield/2.5D and **cannot** produce
overhangs, caves, or stacked layers. No surveyed paper solves
global-simulation-but-infinite-tileable.

## Camp 1 — volumetric & stratified representations (give us overhangs + geology)

- **Arches** — Peytavie, Galin, Grosjean, Mérillou, *Computer Graphics Forum*
  2009, DOI `10.1111/j.1467-8659.2009.01385.x`. The canonical per-column
  **material stack**: a 2D grid where each column is an ordered list of typed
  layers (air, water, sand, bedrock, rock) by thickness. *"Overhangs, arches
  and caves can be easily created by inserting an air layer between two bedrock
  layers."* Hybrid model: discrete stack stores materials, an implicit
  convolution surface sculpts/polygonizes.
  **Citation correction:** earlier internal notes miscited this as "Peytavie,
  Galin, Grosbellet, Akkouche" — the verified author list is **Grosjean,
  Mérillou**.

- **Real-time Rendering of Stack-based Terrains** — Löffler & Müller, VMV 2011.
  Independently confirms material stacks *"combine the simplicity of 2D height
  fields and the extended modeling capabilities of 3D volumetric data"*; renders
  arches/overhangs/caves in real time.

- **QuadStack** — Graciano, Rueda-Ruiz, Pospíšil, Bittner, Benes, *IEEE TVCG*
  27(9) 2020/21, DOI `10.1109/TVCG.2020.2981565`. Modern compression + direct
  rendering for the Benes/Forsbach + Arches stack model: per-column run-length
  attribute intervals, **decoupling material/density from layer heights**, in a
  quadtree. Handles arches & overhanged cliffs. **Representation only — not a
  generator or simulator**, and a *bounded fixed volume*: explicitly lacks the
  out-of-core streaming GigaVoxels has.

- **Feature-based volumetric terrain generation** — Becher, Krone, Reina, Ertl,
  I3D 2017, DOI `10.1145/3023368.3023383`. *"A 2D heightfield cannot store
  terrain structures with multiple vertical layers such as overhangs and caves.
  This restriction is lifted if a volumetric data structure is chosen."*

- **Terrain Amplification with Implicit 3D Features** — Paris, Galin, Peytavie,
  Guérin, Gain, *ACM TOG* 2019, DOI `10.1145/3342765`. **The most directly
  relevant paper.** Encodes feature shape **and** terrain geology as
  construction trees of implicit primitives, guided by stratified-erosion and
  invasion-percolation processes. *"Capable of importing existing large-scale
  heightfield terrains and amplifying them"* with slot canyons, sea arches,
  stratified cliffs, hoodoos, and karst cave networks — i.e. an **amplification
  layer that rides on top of a base field** rather than replacing it.
  - *Refuted overreach:* the claim that Becher 2017 "automatically generates an
    SDF-like model that could feed a per-voxel field" was killed 1-2. The
    volumetric capability is real; the automatic-SDF-feed inference was not
    supported. Whether Paris-2019 construction trees can be evaluated **lazily
    per-point** (vs. requiring a baked regional pass) is the open question that
    decides how cleanly this maps onto our octree — see Open Questions.

## Camp 2 — erosion & tectonic simulation (give us plausibility, but heightfield-only)

- **Large Scale Terrain Generation from Tectonic Uplift and Fluvial Erosion** —
  Cordonnier, Braun, Cani, Benes, Galin, Peytavie, Guérin, *CGF* 35(2):165-175,
  2016, DOI `10.1111/cgf.12820`. First CG method combining tectonic uplift with
  fluvial erosion via the geological **stream power equation**. *"Given a
  user-painted uplift map, we generate a stream graph over the entire domain."*
  Co-author Jean Braun is a geomorphologist. The stream power law is now the
  standard governing equation for CG fluvial erosion.

- The same group continued the line, all attacking the **cost** of iterative
  simulation while staying heightfield/2.5D:
  - Schott, Paris, Fournier, Guérin, Galin — *Large-scale Terrain Authoring
    through Interactive Erosion Simulation*, ACM TOG / SIGGRAPH 2023, DOI
    `10.1145/3592787`. Works in the **uplift domain** for interactive
    incremental authoring.
  - Tzathas, Gailleton, Steer, Cordonnier — *Physically-based analytical erosion
    for fast terrain generation*, CGF 2024, DOI `10.1111/cgf.15033`. Closed-form
    solutions to the stream power law: *"time… acts as the parameter of a
    mathematical function"* (a 2D multigrid spatial solve remains).
  - *Terrain Amplification using Multi-scale Erosion*, ACM TOG / SIGGRAPH 2024,
    DOI `10.1145/3658200`. Thermal + stream-power + deposition at multiple
    scales; amplifies a low-res heightfield into a high-res hydrologically
    consistent one — **no volumetric output, no stratified geology**.

**Structural limit:** all of Camp 2 stores one elevation per column. Overhangs,
caves, arches, and stacked geology are definitionally impossible in this
representation. They produce a plausible *base surface*, not the 3D structure.

## The crux: infinite / tileable / streamable simulation — UNSOLVED

No surveyed paper solves it.

- Cordonnier 2016 simulates a stream graph *"over the entire domain"* — global,
  O(area), no boundary-stitching.
- Lim, Tan, Bhojan — *Visually Improved Erosion Algorithm for the Procedural
  Generation of Tile-based Terrain*, arXiv:2210.14496, 2022. Despite "tile-based"
  in the title, a "tile" is a **single heightmap node/pixel**, not a streamable
  world chunk; the whole map is one connected drainage tree.
- QuadStack is a bounded volume lacking out-of-core streaming.
- *Refuted:* the claim that Schott 2023 supports hydrologically-consistent
  blending between separate patches (relevant to seamless tiling) was killed 0-3.
  **Do not rely on it.**

Global drainage coupling is the obstacle to trivial tiling. Boundary-consistent
regional/hierarchical erosion that stitches seamlessly across independently
simulated tiles is, as of this survey, an **unpublished engineering problem**
(overlapping halo regions + deterministic boundary seeding is the de-facto
answer, but nobody has published it working).

## Coverage gaps (not evidence against — just unverified here)

- **Galin et al. "A Review of Digital Terrain Modeling"** (Eurographics STAR,
  CGF ~2019) almost certainly exists (Galin, Guérin, Peytavie, Cordonnier,
  Benes, Gain) but no claim about it survived verification — treat specifics as
  unconfirmed; it's still the recommended anchor survey to read directly.
- **ML/diffusion terrain (2021–2025):** no claim survived the adversarial pass.
  No verified finding on whether diffusion/ML terrain is controllable enough for
  an engine substrate. Prior (unverified): not controllable enough yet.

## Open questions carried into the design

1. Can Paris-2019 implicit construction-tree amplification be evaluated **lazily
   per-voxel** as `f(position) -> (sdf, material)`, or does it fundamentally need
   a baked volumetric pass per region? This decides whether the volumetric
   overlay stays pure. **This is the pivot.**
2. Is there any published boundary-consistent / halo-overlap erosion that lets
   independently simulated tiles stitch into a global drainage network?
3. Does a newer (2022–2025) survey supersede Galin 2019?
