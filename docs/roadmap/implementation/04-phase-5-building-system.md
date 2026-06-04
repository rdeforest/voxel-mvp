# Phase 5: Building System

**Goal:** Place structures that integrate with voxel terrain.
**Version target:** 0.0
**Status:** Complete for v0.0 thesis defense. See
`../../completed/implementation-04-phase-5-building-system.md`. Deferred
items moved to Phase 5.5 (next chapter).

## This was the thesis defense

The whole v0.0 effort was a setup for this phase. Phase 0 gave you a
world to walk on; Phase 2 gave you the verbs; Phase 5 had to prove
that placing things into the world worked with the same physical rules
as the terrain itself.

## Tasks

- **Hybrid building approach:**
  - Voxel building: place/remove material voxels (walls, floors from
    terrain material).
  - Prefab building: snap-together pieces for doors, roofs, stairs.
- Building piece catalog (MVP):
  - attachment parts: hinge, angle bracket, ...
  - mechanical parts: spring, axle, ...
  - assemblies: wall/floor/ceiling, stairs, door frame, ...
- Snap point system: pieces detect and align to adjacent pieces.
- Ghost preview showing placement before confirming.
- **Structural integrity system (the killer feature):**
  - Every voxel and prefab piece has a support value.
  - Support propagates from ground contact upward, weakening with
    distance.
  - Material-dependent: stone supports more than wood, wood more than
    dirt.
  - Color-coded visual feedback (green → yellow → red → collapse),
    same system for terrain AND player structures.
  - Cave ceilings follow the same rules: unsupported spans collapse
    over time.
  - Player can reinforce caves with wooden beams or stone pillars.
- Voxel-to-prefab interface: prefab pieces anchor to voxel terrain
  seamlessly.
- Foundation carving: building foundations carve into terrain voxels
  automatically. [Deferred to v0.1.]
- Workbench radius requirement for building. [Deferred to v0.9.]

## Key decisions

- **Unified structural integrity** is the core innovation. The same
  algorithm that decides whether your wooden roof is supported also
  decides whether a cave ceiling stays up. One system, one visual
  language, one set of rules. This is the thing that makes people say
  "oh, THAT'S why you'd use voxels."
- **Two building modes:** Voxel mode (free-form sculpting) and Prefab
  mode (structured snap pieces). Voxel mode is unique to this engine.
- **Cave reinforcement:** When you mine into rock, the exposed ceiling
  gets evaluated for structural support. If the span is too wide, it
  starts showing yellow/red. Place a pillar and it turns green. This
  makes mining a spatial engineering puzzle, not just "click rock, get
  ore."
- **Material angle of repose (simplified for 0.0):** Dirt and sand
  voxels above a certain slope angle will "slump" — converting to a
  physics object that settles. For 0.0, this can be a simple threshold
  check on exposed faces. Full angle-of-repose simulation with material
  consistency is v0.1.

## Done when

You can build a house partially carved into a hillside, with voxel
stone walls that blend into the rock face, a door, a roof, and visual
feedback showing structural integrity. You can dig a wide cave and
watch the ceiling turn yellow, then place pillars to stabilize it.

## v0.0 checkpoint outcome

**Answered: yes.** The thesis is largely architectural, and
architectural theses are defensible by argument. The conversation
around the design — the role-vs-matter distinction, the event-bus
pattern, the multi-grid approach for vehicles, the fracture-as-mesh-
extraction insight — has stress-tested the architecture and surfaced
plausible answers to every seam found so far. The v0.0 work proved out
the foundation; the design conversation proved out the path forward.

Proceeding to v0.1.
