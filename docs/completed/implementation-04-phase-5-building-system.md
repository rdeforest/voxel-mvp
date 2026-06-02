# Completed: Phase 5 — Building System

Maps to [`../roadmap/implementation/04-phase-5-building-system.md`](../roadmap/implementation/04-phase-5-building-system.md).

## What shipped

The thesis defense. Parts placeable in the world, voxel and part
support unified under one set of rules, cave reinforcement working as
a gameplay mechanic.

- **Parts** as rectangular prefab pieces placeable into the world
  (axis-aligned cell footprints, 90° rotation only).
- **Structural integrity** — per-cell support values for both terrain
  and parts, propagated from ground contact via worklist-fixpoint
  flood-fill, weakened by material-specific decay.
- **Cave reinforcement** — exposed cave ceilings evaluated for support;
  unsupported spans visualised in yellow/red; placing a pillar
  stabilises them.
- **Material decay rates** in `.tres` files: STONE (0.05), WOOD (0.10),
  DIRT (0.20) — the decay is what makes stone span gaps and dirt
  crumble.
- **Color-coded structural visualisation** for both terrain and parts.
  Same visual language across both kinds of matter.
- **Lazy expansion bounded by material decay** — cascade stops where
  support reaches `FALL_THRESHOLD` (~20 cells for STONE). Keeps the
  cost per edit bounded.
- **Per-column bedrock detection** (`_lowest_registered_y`)
  distinguishes real bedrock from suspended mass.
- **Falling parts** as `RigidBody3D` when their support drops to zero.
- **Workbench radius** requirement deferred — Valheim mechanic of
  questionable value.

## Key decisions taken

- **Hybrid voxel + prefab approach with matching-SDF-shell technique
  (Option A2).** Parts have an SDF representation in addition to their
  collision/mesh, allowing them to interact with terrain SDF
  operations.
- **Refuse-don't-deform principle for placements** that can't satisfy
  constraints.
- **Object terminology committed:**
  - **Part** — board, beam, sheet.
  - **Assembly** — door, wagon (composed of Parts and sub-Assemblies,
    may have Behaviors).
  - **Mold** — captured SDF region for terrain stamping.
  - All three are kinds of **Schematic**.
  - A **Construction Action** instantiates a Schematic as a
    **Placement** in the world.
  - Placements connect via **Joints**.
  - Schematics can have **Behaviors**.
  - **Sites** are regions with metadata (deferred).
- **Action-as-data extended.** Construction reuses the v0.0 `Action`
  infrastructure rather than building its own placement system.
- **Mid-break destruction deferred** — whole-prefab destruction only
  for Phase 5. Real fracture is Phase 5.5c.
- **In-game Schematic editor deferred** to v0.9+. Hand-authored `.tres`
  files are fine for the v0.0 demo.
- **Non-adjacent linkages (cables, ropes) deferred.**
- **Performance Fermi-estimated:** 36× headroom on worst case at the
  time of the design pass. Press on.

## Lessons learned

- **The "what if a voxel is two types of cell?" question is a category
  error.** Resolved by the role-vs-matter distinction: voxels store
  *what the matter is*; roles live in sidecar indexes. Captured in
  [design principle #6](../roadmap/design/01-principles.md).
- **Materializing the same physical rules over different data
  structures (voxels and parts) was the v0.0 architectural commitment
  that made the unified visualisation possible.** The components had
  to be designed with the same vocabulary (support values, decay,
  thresholds) before they could share a visual language.
- **The dichotomy between part-support and terrain-support algorithms
  is a workaround, not the destination.** They share the *same physical
  semantics* but compute differently (terrain: worklist-fixpoint flood
  fill; parts: per-frame recompute bottom-up). The unified answer comes
  with DC-QEF — one field, one mesher, one propagation algorithm.
  Captured in [the DC-QEF transition chapter](../roadmap/implementation/14-dc-qef-transition.md).

## Deferred to v0.1+ (with reasons)

| Item | Why deferred |
|------|--------------|
| SDF seam matching (Option A2) | Sub-cell parts can't be represented at 1m voxel resolution; better answered by DC-QEF transition. |
| Welding / joining (intersecting parts mutually support) | Needs a joint/weld data model; current `_cell_to_part` stack doesn't represent shared structural attachment. → FEAT030. |
| Load propagation (top-down weight pass) | Pairs with falling damage and SDF-seam-as-physics. |
| Falling damage | Needs a damage model. → FEAT028. |
| Hinge-at-boundary collapse | Polish on falling drama. → FEAT029. |
| Foundation carving | Constructions automatically carving terrain voxels — deferred to v0.1. |
| Workbench radius | Valheim mechanic; may not survive scrutiny. → FEAT075 if at all. |
| In-game Schematic editor | Hand-authored `.tres` is fine for v0.0. → FEAT074. |
| Specialised joinery pieces (doors, stairs, mating constraints) | Rectangular parts demonstrate the system. |
| Snap point authoring UI | Data structure exists; UI is FEAT073. |
| Free-form placement with physics settle-to-construction | Architectural change; current grid-aligned demo carries thesis. (Partly addressed by free part placement, `9f2e36a`.) |

## Validation

Build a house partially carved into a hillside with voxel stone walls,
a door, a roof. Dig a wide cave, watch the ceiling turn yellow, place
pillars, watch it turn green. **Thesis defended.**

## v0.0 checkpoint outcome

The v0.0 question — "is this as good of an idea as I think it is?" —
got answered yes. Proceeding to v0.1 (Phase 5.5 and onwards).
