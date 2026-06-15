# Known Hard Problems

Open architectural questions that don't yet have committed answers, or
where the answer needs more thought before implementation. Captured so
they can be picked up cold without rediscovery.

## Sub-meter precision without the cubic penalty

The naive "shrink voxel size" answer has a real-world cost closer to
3–5× for most operations, not 8×, because real voxel engines are
sparse and surface-dominated (memory compresses aggressively for
fully-solid and fully-air regions; meshing and physics costs scale
with surface area, not volume). But there are better answers than
shrinking the global grid:

1. **Multi-resolution sidecar data.** Render and collide at 1m; track
   structural integrity at 0.5m or 0.25m in a separate sparse
   dictionary that only exists for modified regions. The hard part is
   the coupling — what happens visually when a sub-region of a render
   voxel fails? See Phase 5.5c (fracture as mesh extraction) for the
   answer.

2. **Stress and strain as a continuous field, not a per-cell value.**
   A stress tensor sampled at whatever resolution the physics wants,
   computed via something closer to FEM than to cellular automata.
   Fractures happen along computed surfaces in continuous space and
   produce arbitrary-shape debris. This is Teardown's approach.

3. **Hybrid (voxels for matter, mesh for fracture).** The pragmatic
   shipping option. The voxel grid stays at 1m. Fractures aren't
   aligned to it because fractures are a *transition event* that
   produces non-voxel outputs (rigid bodies). The illusion of sub-meter
   fracture precision comes from the moment of breaking, not the
   underlying data structure. Recommended for v0.2.

4. **Per-grid voxel size.** Locomotive at 0.25m, boat at 0.5m, main
   world at 1m. Costs nothing in the main world; gives the precision
   where it matters.

5. **DC-QEF with adaptive octree (the field-based answer).** Local
   octree subdivision wherever a fine brush is imprinted. Cells stay
   cubes, but the *surface* threaded through them is sub-cell-
   accurate via QEF. This is the principled long-term answer; see the
   geometry chapter.

## FEM (Finite Element Method) for fracture direction

FEM is the numerical technique behind real-world structural
engineering. Subdivide an object into many small elements (tetrahedra,
hexahedra), approximate the physics as a system of linear equations
relating each element to its neighbors, solve the system, get a field
of stress/strain values across the whole object. It tells you not just
"this is supported" but "this is under 12kN of tension along this
axis, exceeding stone's tensile strength of 8kN/m², so a crack will
propagate along this plane."

Relevance to this project: the flood-fill structural integrity is fine
for the global "is this voxel supported?" question. But for
determining *fracture direction* during a collapse event, a tiny
localized FEM-ish calculation gives much better results than voxel-
aligned cubes. The plan: keep the flood-fill cheap and continuous,
reach for FEM-style math only when a fracture actually happens, in the
affected region only. This is the foundation under Phase 5.5c.

FEM at game-tick rates over the whole world would be prohibitive. FEM
in a small region during a single collapse event is tractable. The
difference is whether it's a continuous simulation cost or an event-
driven one.

## Mob pathfinding on voxel terrain

This is legitimately one of the hardest problems in the project.
Heightmap games generate a 2D navmesh and call it done. Voxel terrain
is 3D, deformable, and has caves — navmesh generation is expensive
and invalidated every time terrain changes.

**Approaches, from simplest to most correct:**

1. **Raycast steering (v0.9 starting point):** Enemies cast rays
   ahead and to the sides, steer away from obstacles, chase player by
   direction. No navmesh at all. Works for simple melee rushers in
   open terrain. Fails in caves and around structures.

2. **2.5D navmesh per chunk:** Generate a walkable surface mesh from
   the voxel data (essentially a heightmap extracted from the voxel
   volume for each chunk). Recompute when chunks are modified.
   Handles surface navigation well but doesn't help with multi-level
   cave navigation.

3. **3D navigation grid:** A coarse voxel grid (2m resolution)
   marking walkable, climbable, and blocked cells. A* pathfinding on
   this grid. Handles caves and multi-level structures. Expensive to
   compute but can be done incrementally (only recompute modified
   chunks).

4. **Hierarchical pathfinding (HPA*):** Pre-compute region
   connectivity at a coarse level, then fine-path within regions.
   This is what Dwarf Fortress eventually moved toward. Good for large
   worlds but complex to implement.

**Recommendation:** Start with option 1 for outdoor enemies, option 3
for dungeon enemies. Claude Code can generate the A* implementation
and grid extraction; the hard part is making movement LOOK natural
(smoothing paths, avoiding jitter, handling slopes). Budget significant
time for feel-testing.

**The "does it look right" problem** is real and can't be automated.
Record video of enemy movement, watch at 0.5x speed, identify what
looks wrong. Common issues: path oscillation, inability to handle
ledges, getting stuck on terrain features, unnatural turning.

## Planet-scale world (post-MVP)

The dream: sail across a seemingly infinite ocean for in-game months
and discover a new continent, on an Earth-like spherical planet.

**This is achievable but requires architectural decisions made early:**

- **godot_voxel "double" builds:** Zylann publishes builds with large
  world coordinate support (64-bit floats). Use these from day one
  even if you don't need them yet. No cost, prevents a painful
  migration later. **Already committed.**
- **Cube-sphere projection:** Map 6 cube faces to a sphere surface.
  Each face is a flat voxel world internally, with projection
  distortion handled at the rendering layer. This is how No Man's Sky,
  Minecraft-inspired planet mods, and various space games do it.
- **Tectonic simulation (generation-time only):** Generate plate
  boundaries, mountain ranges, and ocean basins from tectonic rules,
  then use these as inputs to the biome noise functions. Doesn't need
  to be real-time — run it once during world creation.
- **Ocean:** The hardest part for a voxel engine. Heightmap engines
  get ocean "for free" (it's just another height value). Voxel oceans
  need either a water surface plane with wave simulation (visual only,
  not voxel) or actual fluid voxels (expensive). For sailing, a
  shader-based ocean surface with buoyancy physics is the pragmatic
  choice.

**Key early decision:** Use the godot_voxel double-precision build.
Everything else can wait until post-MVP, but the coordinate precision
cannot be retrofitted.

## Physics-vs-CRDT tension (network layer)

Treated in detail in [the network architecture chapter](05-network-architecture.md).
Summary: static geometry edits merge as a CRDT; live physics
simulation cannot. Direction taken is regional authority for active
simulation while geometry stays fully decentralized, but the boundary
between "active sim" and "merged geometry" needs more thought before
implementation. This is the single deepest open question in the
network design.

## DC-QEF LOD seam handling

Treated in detail in the
[DC-QEF transition chapter](../implementation/started/14-dc-qef-transition.md).
Summary: naive DC across an octree LOD boundary cracks. Transvoxel
exists *specifically* to stitch LOD cracks; replacing it with DC means
solving those seams ourselves via restricted/balanced octree +
matching subdivision on shared edges, or via Manifold DC. This is the
*real* work of the transition — the base mesher is straightforward;
the seams are the time sink.
