# Project Status

> **Maintenance contract:** the "Resumption Brief" must reflect the current
> moment. The "Tracker" below it can drift a little. If updating this doc
> after a session takes more than ten minutes, it's too big — shrink it.

---

## Resumption Brief

*Last updated: end of multi-axis rotation + part decay propagation session;
scope review for v0.0 close-out*

**Where you are:** the building system is functionally complete. Parts are
parametric (`dimensions: Vector3` drives mesh, collision, and footprint), come
in four flavours (board, plank, stud, beam), rotate around all three axes in
90° steps (KEY_R/T/Y), and propagate support through stacked chains with
material decay. The strain visualisation reads the support gradient on the
part's surface via emission (so future textures stay legible). Removing a part
from under a stack correctly re-evaluates the upper parts; thin stacked parts
within a single voxel cell are disambiguated by `placement_y` ordering.

**The one missing v0.0 piece is cave integrity.** Phase 5's killer demo from
the roadmap — "dig a wide cave, watch the ceiling strain, place pillars to
hold it" — currently doesn't work because `DigAction` modifies the SDF without
registering the newly-exposed wall/ceiling cells with `StructuralIntegrity`.
Without those registrations, the cave's geometry is invisible to support
propagation.

**Pick up here:**

1. **Cave integrity.** In `DigAction.execute()`, after the SDF modification,
   walk the dig sphere's surface and `register_voxel` any still-solid cell
   adjacent to a newly-air cell. Default material STONE for v0.0. Also extend
   `_calculate_support` for terrain voxels to recognise Parts as supporters
   (currently checks natural terrain + other terrain voxels only) — this makes
   "wooden pillar supports stone ceiling" work without a special case.

2. **SDF seam matching (Option A2).** After cave integrity, the remaining
   architectural item: placed Parts should write matching SDF samples into the
   cells they occupy so the Transvoxel mesher produces a clean visual seam at
   the part-terrain boundary. Makes the carved-into-hillside aesthetic land.
   Optional for v0.0 thesis defense; required for a photogenic trailer.

3. **Wrap v0.0.** Record the cave reinforcement demo. Write the v0.1 scope
   doc. Everything from the "deferred" list (planning mode, sub-assemblies,
   free-form physics placement, snap-point UI, hinge collapse, falling damage,
   fallen-dirt-as-terrain, terrain shader strain, KSP-style dimension UI,
   more dig/fill shapes) belongs to v0.1's question: "can I make it fun?"

**Active mental state to preserve:**

- `voxel_data: Dictionary` is terrain-only. `part_registry: Dictionary[Node3D, PartData]`
  is parts. Both live on `StructuralIntegrity`.
- `_cell_to_part: Dictionary[Vector3i, Array[Node3D]]` is a per-cell *stack*
  of parts — multiple thin parts in one voxel cell is normal, ordering is by
  `placement_y`.
- Terrain support uses a worklist fixpoint (dirty queue, `PROPAGATION_BUDGET`).
  Part support is recomputed fresh each frame via `_recompute_part_support()`
  bottom-up by `placement_y`, then strain accumulates against `delta`.
- Part collapse lives in SI (`_collapse_part`), not in `CollapseDetector`.
  CollapseDetector is terrain-only.
- Strain visual: emission tracks `get_support_color(support)`. Pulse only
  during strain window. `_apply_part_visual` keeps original albedo so the
  surface stays legible (matters when textures arrive).

---

## Tracker

### v0.0 — Phase status

| Phase | State | Notes |
|-------|-------|-------|
| 5 — Building System | Functional; cave integrity remains | Parts (parametric, multi-axis rotation, decay propagation) + part-level structural integrity done; cave integrity + SDF seam matching outstanding |

### Bugs

| ID | State | Notes |
|----|-------|-------|
| 2c | Closed | Player fall-through fixed via `Action.validate()` refusal |
| 2a | Deferred | Flatten clears only one sheet above — cosmetic; deferred until building replaces flatten |

### Architectural commitments worth not re-litigating

- **Track Godot 4.6-stable + godot_voxel v1.6.** Pinned in `tools/versions.env`.
- **Double-precision godot_voxel build from day one.** Non-retrofittable.
- **No engine forks.** Pull upstream directly.
- **`godot/modules/voxel` symlink, not `custom_modules`.**
- **Worklist-fixpoint propagation for terrain support.** Not generalised
  until a second customer (fatigue/fluid/temperature) appears.
- **Part support computed fresh per frame, sorted bottom-up by `placement_y`.**
  No dirty queue. Reasoning: parts depend only on strictly-lower parts, so
  sorting eliminates the fixpoint problem; recompute is cheap (one decay-minus-max
  pass per part).
- **Per-cell *stack* of parts (`Array[Node3D]`), not single-cell-per-part.**
  Multiple thin parts share a voxel cell when stacked vertically; `placement_y`
  disambiguates which is below which.
- **Signals for support changes** (`voxel_support_increased`). No event bus
  until three unrelated listeners demand it.
- **Strain timer accumulated against physics `delta`,** not wall-clock —
  pause-correct.
- **Action-as-data; targeting at the call site.** Actions take final
  computed parameters, not raw input.
- **Refuse-don't-deform.** Actions refuse via `validate()` rather than
  silently adjusting state. Extended to physics state via FillAction's
  `intersect_shape` check before filling on a RigidBody3D.

### Done this v0.0 cycle (recent)

- Multi-axis Part rotation (`Vector3i` rotation, KEY_R/T/Y bindings,
  rotated-AABB-based footprint + visual placement shift).
- Part support propagation with material decay (was binary; now [0,1]
  with `support - decay` per hop). Direct-supporter selection avoids
  parts "seeing through" other parts to terrain.
- Per-cell stack semantics: thin parts stacked in one cell are
  ordered by `placement_y`; removing a lower part correctly orphans
  the upper.
- Strain visual via emission on original albedo (textures will stay
  legible when added).
- Hover tint: raycast-hit Part shows its current support color.
- Bug fixes: red-after-fall, fill-on-rigid-body tunneling, terrain
  edits not waking sleeping rigid bodies, beam-on-beam stacking
  detection.
- Parametric Parts (`Part.dimensions: Vector3` drives procedural
  mesh/collision/footprint); board.tscn deleted in favour of procedural
  build, four `.tres` files now define the catalog.
- 14-item code review cleanup pass: removed dead fields, deduplicated
  `_neighbors`, `dirty_queue.pop_back()`, unified EditPreview's Flatten
  basis through `preview_basis` callable.

### Deferred to v0.1 (the "can I make it fun?" question)

| Item | Why deferred |
|------|--------------|
| Sub-assemblies + planning mode (Dwarf-Fortress queue) | Significant UI work; v0.0 question is about thesis, not workflow |
| Autonomous helpers / tameable fauna executing plans | Same as above; far-future |
| Free-form placement with physics settle-to-construction | Architectural change (RigidBody3D → settle → register as Part); current grid-aligned demo carries thesis |
| Snap point authoring UI | Data structure exists; UI is v0.1 |
| Specialised joinery pieces (door frames, stairs, mating constraints) | Rectangular Parts demonstrate the system |
| Workbench radius | Valheim survival-loop mechanic; doesn't validate voxel-first design |
| Hinge-at-boundary collapse (towers tip rather than lift off) | Polish on falling drama |
| Falling damage (impact → break/crumble) | Needs damage model; v0.1 polish |
| Fallen-dirt-as-terrain (RigidBody3D rejoins SDF when at rest) | Needs settle-detection + SDF rewrite path |
| Partial-dirt-cover support of fallen parts | Needs free-form placement first |
| Terrain strain on mesh surface (replace debug cubes) | Real shader work |
| Highlight parts depending on about-to-fall things | Dependency-graph walk; nice-to-have |
| Player-controlled dig/fill shapes & sizes | UX polish |
| KSP-style parametric Part dimensions in-game | Tooling polish |
| Per-material strain duration; nature-of-change reset scaling | Tuning pass |
| Gap-between-layered-parts (parts can't "see through" missing intermediate parts) | Needs PartData.dimensions; punted |
| Mid-break Part destruction | Whole-part destruction is enough for v0.0 |
| Non-adjacent linkages (ropes, cables) | New data structure required |
| Load propagation (top-down) | Mirror of support propagation; revisit |
| Material fatigue (cumulative strain history) | Only meaningful with mobs (v0.9) |
| In-game Schematic editor | Hand-authored `.tres` is fine; v0.9+ |

### Known limits (recorded, not fixed)

- **Digging strained ceiling resets the gradient.** Newly-exposed cells from a
  fresh dig see their immediate untracked-solid lateral neighbours as
  FULL_SUPPORT (the cliff mass beside the dig is bedrock, structurally), so the
  strain that had developed in the original ceiling doesn't propagate into the
  newly-revealed cells. The shell registration is 1 cell thick — to make
  "digging into orange reveals more orange" work, we'd need either a much
  thicker shell (~20 cells for STONE's decay budget) or a "shallow vs deep"
  detection that distinguishes suspended mass from real bedrock. Both are
  architecturally meaningful. For the v0.0 demo, build wide caves fresh; don't
  iteratively dig the strained area.
- **`_resume_unfinished_floods` budget starvation:** components larger than
  `DETECTION_BUDGET` (500 voxels) take multiple settled frames to fully detect.
- **`PLAYER_CLEARANCE = 1.0m`** in Fill/Flatten is a guess; tune if needed.
- **Part scene layout assumes flat children.** `_collapse_part` reparents direct
  children only; nested scenes would silently break.
- **Hand-authored `Schematic.footprint` is not rotated** by ConstructionAction.
  None currently use it.
- **`FlattenAction` center/plane-point asymmetry** — explicit constructor
  params with a comment; easy to revisit.
- **Terrain debug visuals are cubes that draw through walls** (`no_depth_test`).
  Replacing with surface-shader strain is v0.2.

---

## How to update this doc

After each session:

1. Rewrite the **Resumption Brief** completely. It must reflect *right now*,
   not history. If you find yourself adding to it instead of replacing, the
   item probably belongs in the Tracker.
2. Move "in progress" items in the Tracker to "Done this v0.0 cycle" as they
   finish. Add new entries to Deferred / Known Limits as they emerge.
3. If the Tracker is hard to navigate, it's too big. Move older "Done"
   entries into a one-line summary like "Phase X complete (commit abc123)"
   and trust git for the detail.
4. If updating this doc took more than ten minutes, something is wrong with
   its shape.
