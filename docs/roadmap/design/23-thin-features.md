# Thin Features and the Invisible Grid — discussion brief

*Drafted by Claude (Claude Code session), 2026-09-27, as the starting point for a design chat with
Robert. **Nothing here is decided.** It collects the question, the history, the measurements and
the option space so the chat can start from facts. The manifesto wins if this disagrees with it.*

Repo links below are relative. From a chat that can't follow them, prefix
`https://github.com/rdeforest/voxel-mvp/blob/master/docs/`.

## The question

Robert, 2026-09-26 ([overnight-2026-09-26](../implementation/done/overnight-2026-09-26.md)):

> I want the player to be unaware of the grid. To the degree that it's possible, and it will
> undoubtedly require tricks, I'd like a board placed aligned 10 degrees off of 'North' to look
> about the same as one placed at 0 or 20 degrees.

Robert, 2026-09-27, after reading the Voxel Farm notes: the point of smooth voxels is to show the
industry it can be done, and "it can be done" means **no trade-offs compared to height maps
(Valheim)**. A player should never be able to reason "this board is smoother than that one, so it
must be better aligned with the grid."

The benchmark worth naming precisely: Valheim's *terrain* is a heightmap, but its *building
pieces* are ordinary meshes. A Valheim plank looks identical at every angle and position because
it is not sampled at all. That is the bar.

Robert has gone back and forth on this before (history below) and doesn't have a new answer. The
chat's job: hash it out from every angle — vision, principles, the cost of holding the principles,
the cost of each compromise.

## Where things stand today

| Item                             | Value                                 | Where                                       |
|----------------------------------|---------------------------------------|---------------------------------------------|
| Gameplay / structural cell       | 1.0 m                                 | `scripts/voxel_constants.gd` (`VOXEL_SIZE`) |
| Render / imprint cell            | 1.0 m (`RENDER_SUBDIV_LOG2 := 0`)     | `scripts/voxel_constants.gd`                |
| Collision cell                   | 0.5 m                                 | `scripts/dc/dc_collision_manager.gd`        |
| Parts in the catalogue           | beam 6×2×2, slab 4×2×4, log 0.5×0.5×4 | `assets/parts/*/`                           |
| Thin lumber (board, plank, stud) | none                                  | removed 2026-06-10                          |

- Every placed part is **imprinted into the one SDF field**; identity lives in the PartIndex
  sidecar. There is no part mesh.
- The mesher is dual contouring with a QEF: **one vertex per leaf cell**, built from scalar corner
  samples (linear edge crossings, finite-difference normals).
- By the ~2-sample Nyquist rule, a 1 m lattice resolves features of roughly **2 m and up**. The
  0.5 m log is below that today; it was added when the render cell was 0.25 m.

## History, briefly

1. **2026-05-17 → 06-10: parts were separate objects.** Each part was a spawned `Node3D` with its
   own mesh, collision and support system. The catalogue was real lumber: board 2×0.1×0.012,
   plank 2×0.2×0.025, stud 2×0.09×0.038, beam 3×0.15×0.15. Option "A2" (parts carry a matching
   SDF shell alongside their mesh) was deferred because sub-cell parts can't be represented at 1 m.
2. **2026-06-02 → 06-07: the one-field decision.** [Doc 03](03-dc-qef-geometry.md): "no separate
   'part' data type. The field is the world." Decided: retire the part exception, start the build
   vocabulary fat (logs, stone blocks), commit to an adaptive-density octree (2026-06-05). Thin
   parts became "Tier 2", waiting on the octree ([doc 10](10-adaptive-octree-substrate.md) B5,
   still unticked).
3. **2026-06-10: the switch.** Lumber replaced by fat parts; placement writes the field; PartIndex
   added; PartSupport and the part Node3Ds deleted; EditStore became the only terrain store.
4. **2026-06-12: sub-metre on.** Render cell set to 0.25 m (`RENDER_SUBDIV_LOG2 := 2`); imprints,
   collision and aiming went sub-metre; the 0.5 m log added.
5. **2026-09-13: sub-metre off.** Commit `59ac2f4` ("WIP: unreviewed claude-code audit output")
   set the knob back to 0. **No reason is recorded anywhere.** Worth reconstructing before
   deciding anything, because it's the one data point about what sub-metre actually cost in play.

Teardown was cited for its physics and fracture, never as a representation argument. See the
multi-grid option below for the part of Teardown that *is* relevant here.

## What's been measured

From [reference note 09](../reference/09-perceptual-lod-research.md) (placed axis-aligned stones,
one scene, one seed):

- At the 1 m floor the stones are **6–13 px off the field at p50, 17–40 px at p95**. A distant
  generated ridge is 0.00 / 0.23 px. Refinement order and collapse aren't the cause; the floor's
  reconstruction is.
- **The error depends on phase against the lattice.** Faces that fall exactly on lattice planes
  read as exact-zero corners, which count as outside: **1 m lintels vanish completely.** This is
  already the "better aligned, so it looks different" effect Robert wants gone, before rotation
  enters.
- **Exact Hermite data at the same 1 m lattice** (true crossings and normals) puts the QEF vertex
  on the stone at 0.000 m p50. It fixes sharpness, not feature size.
- **A 0.25 m lattice** for both imprint and mesh brings the stones to 0.37 / 1.75 px, at 27× the
  cells in a ±32 m window. Refining only one of imprint or mesh leaves 47–66% of the face area
  more than 0.25 m from the mesh. Aligned 0.25 m phases produce 300+ non-manifold edges.
- All of this is **axis-aligned**, the best case. Nothing has measured rotated parts yet.

From [reference note 11](../reference/11-voxel-farm-thin-features.md): Voxel Farm stated the
~2-voxel limit (0.3 m voxels → 0.6 m features) and never solved it in general. Its escapes were
finer voxels, aligning content to the grid, and textures at distance. The alignment trick is
exactly what Robert rules out.

## The limits, separated

These get conflated; they have different fixes.

1. **Feature size (Nyquist).** A sheet thinner than the sample spacing whose corners all share a
   sign is invisible to *any* contouring scheme. Fixes: finer sampling where the feature is, or
   data that isn't corner samples.
2. **Two surfaces in one cell.** One vertex per cell can't hold both faces of a board. Fixes:
   local subdivision, or Manifold DC (multiple vertices per cell).
3. **Reconstruction error at the floor.** Linear crossings and coarse gradients across an SDF that
   kinks inside the cell. Fix: exact Hermite data.
4. **Grid dependence (the actual complaint).** Quality varies with phase and angle relative to the
   lattice. Limits 1–3 all produce it. Driving them below perception at play distance is the goal;
   removing any one alone doesn't.

For a real 2×4 (38 mm binding thickness, per doc 03), limit 1 alone needs roughly 10–20 mm
spacing wherever lumber exists.

## Principles in play

- **Non-negotiable #1: terrain and construction are the same kind of data.** "Anything that
  reintroduces a part/terrain dichotomy is regression." Separate part meshes violate this as
  written. Choosing them means amending the manifesto, not just a design doc. Say that explicitly
  if the chat goes there.
- **Non-negotiable #7: the grid is a multi-channel spatial database.** Channels can differ in
  resolution. This leaves room for data that isn't a scalar lattice: exact brush data, Hermite
  channels, or finer local grids.
- **Non-negotiable #6 and #8: hardware keeps improving.** Cost that scales with *detail* is
  acceptable; cost that scales with *world size* must be fixed structurally. Doc 03's budget
  already assumes 5 mm detail at ~1000 build sites (~1.5 TB for 100 km²).
- **Infinite programming resources.** "Manifold DC is hard" is not a reason. Hardware is.
- **Faking surfaces** is a named failure mode: rendering something the data doesn't hold.
- **Edits are first-class:** player edits render identically to generated terrain at every LOD.

## Option space

Not exclusive; several combine. Costs are in the two currencies the manifesto allows: hardware,
and principle.

- **A. Finer uniform floor** (0.25 → 0.0625 m). Fixes 1–3 down to its own spacing.
  Principle cost: none. Hardware: ×8 cells per halving in a dense volume (note 09 measured 27× in
  a ±32 m window at 0.25 m); an uncommitted LOG2=4 (0.0625 m) run reached 725 M cells. Still
  grid-dependent below its own Nyquist.
- **B. Local adaptive floor near edits and the foreground** (note 09 option 1). Fixes 1–3 where
  applied. Principle cost: none; this is doc 10's plan. Other cost: touches EditStore leaf size,
  the save format, and issue #10 (a 1 m write flattens finer leaves inside it).
- **C. Exact Hermite data for edited leaves** (note 09 option 2). Fixes 3. Principle cost: none
  (a channel, #7). Hardware: storage per edited leaf. Doesn't help 1 or 2 alone.
- **D. Manifold DC / multi-vertex cells.** Fixes 2. Principle cost: none. Other cost: mesher
  rewrite; topology-safe collapse is the hard part.
- **E. Keep the analytic brush as a field channel,** evaluated exactly at any sampling. Fixes 1–3
  for brush-made shapes. Principle cost: arguably none (#7), but doc 03 §4 chose to discard shape
  identity. Hardware: evaluation cost; CSG history grows; still needs B or D to *show* thin
  features.
- **F. Per-assembly local grids (multi-grid).** Removes rotation dependence by construction.
  Principle cost: none if each grid is the same field type. Other cost: seams where grids meet
  (wall into rock); structure and meshing across grids.
- **G. Separate part meshes** (the pre-06-10 model). Fixes everything, for parts only. Principle
  cost: **violates non-negotiable #1**. Hardware: cheap. Brings back the part/terrain split
  everywhere downstream.
- **H. Shader / normal-map detail at distance.** Appearance only. Principle cost: risks "faking
  surfaces". Hardware: cheap. Voxel Farm's distance answer.

Notes on the less obvious ones:

- **F, multi-grid.** [R: recollection, unverified] Teardown gives each body its own voxel volume,
  oriented with the body, so a rotated plank is axis-aligned in its own frame and looks the same
  at any angle. This project already reserves `GRID_ID` in every event payload for multi-grid
  (roadmap 5.5d, deferred to v0.2 for vehicles). A board placed at 10° on its own grid is a 0°
  board locally. That removes rotation dependence but not phase dependence, and it doesn't
  help terrain. The hard question is the join: a beam set into a rock face is two grids meeting.
- **E and C** are the same idea at different strengths: keep what the brush knew instead of
  collapsing it into corner samples. Note 09 measured C fixing axis-aligned sharpness at 1 m cost.
- **B** is the path the design docs already chose (doc 10, doc 11 "sub-metre for free later"). It
  was on from 06-12 to 09-13, and nobody recorded why it was turned off.

## Questions for the chat

1. **What exactly is the bar?** "Indistinguishable at any angle and phase at play distance", with
   a pixel threshold? Or "no artefact a player would attribute to alignment"? A measurable bar
   makes every option testable.
2. **What is the thinnest thing the game must build?** Real 38 mm lumber, or a stylised "board"
   (say 0.1–0.2 m)? This sets the spacing requirement by an order of magnitude.
3. **Is non-negotiable #1 about data or about behaviour?** If a part is imprinted into the field
   (physics and structure are unified) but also carries exact geometry in another channel for
   rendering, is that a dichotomy? Where exactly is the line between "a channel" (#7) and
   "faking surfaces"?
4. **Multi-grid now instead of v0.2?** If rotation invariance comes free from per-assembly grids,
   does the join problem (grids meeting terrain) become the real thesis problem?
5. **Why was sub-metre turned off on 2026-09-13?** Reconstruct from `59ac2f4`'s diff and the
   session logs around it before choosing between A and B.
6. **Terrain too?** Thin natural features (spires, ledges, roots) hit the same limit. Is the goal
   grid invisibility for construction only, or for all matter?

## Evidence we could gather before or during the chat

- **A grid-invisibility probe:** place the same board at angles 0/5/10/20/45° and several phases,
  mesh at 1 m / 0.25 m / 0.0625 m, and report mesh-to-intent error in metres and pixels. Note 09's
  harness already does phases for axis-aligned stones; rotation is the missing axis. The output
  is a table that answers question 1 for each option.
- **Recover the 09-13 reason** (question 5).
- **Size the Tier 2 cost:** cells and memory for one house of 38 mm lumber at 10 mm local spacing,
  versus doc 03's budget.
