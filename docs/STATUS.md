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

**Cave integrity is in place.** Phase 5's killer demo from the roadmap —
"dig a wide cave, watch the ceiling strain, place pillars to hold it" —
works via two cooperating mechanisms:

1. **Initial registration.** `DigAction` registers cells with at least one
   air neighbour as the dig's 1-cell-thick shell. Same path used by fresh
   digs and collapse cavities.

2. **Lazy expansion driven by bedrock semantics.** A per-column index
   (`_lowest_registered_y`) distinguishes real bedrock (untracked solid in a
   column with nothing tracked below) from suspended mass (untracked solid
   above registered cells). In `_calculate_support`, lateral untracked
   neighbours grant FULL_SUPPORT only when bedrock; non-bedrock cells get
   lazy-registered into the integrity system and propagation extends the
   tracked region. Cascade depth is bounded by material decay (cells stop
   triggering lazy registration once their own support drops to or below
   FALL_THRESHOLD), so a STONE chain reaches ~20 cells before saturating.

Parts whose support depends on still-dirty terrain voxels (or other
in-limbo Parts) are flagged `in_limbo` and pause their strain timer until
dependencies settle — avoids a transient zero from triggering a spurious
3-second countdown.

**Pick up here:**

1. **Test the cave demo end-to-end.** Dig a wide cave, watch the gradient
   settle (a few frames of propagation), see colour develop from blue at the
   walls toward red at the centre. Verify that digging further into the
   strained region doesn't reset the gradient (the lazy expansion should keep
   the strain). Verify that placing wood beams under the ceiling recovers
   support.

2. **SDF seam matching (Option A2).** After cave integrity is validated, the
   remaining architectural item: placed Parts should write matching SDF
   samples into the cells they occupy so the Transvoxel mesher produces a
   clean visual seam at the part-terrain boundary. Makes the
   carved-into-hillside aesthetic land. Optional for v0.0 thesis defense;
   required for a photogenic trailer.

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

- **`_resume_unfinished_floods` budget starvation:** components larger than
  `DETECTION_BUDGET` (500 voxels) take multiple settled frames to fully detect.
- **`PLAYER_CLEARANCE = 1.0m`** in Fill/Flatten is a guess; tune if needed.
- **Lazy-expansion cascade per dig is bounded by material decay budget.** For
  STONE (decay 0.05), the cascade reaches ~20 cells before support hits zero
  and lazy registration stops. For a very wide cave under a tall cliff, this
  means structural mass beyond ~20 cells above the ceiling isn't tracked —
  fine for support computation (the chain is already zero there) but means
  the load propagation that v0.1 will add will need its own cascade rules.
- **`_recompute_column_low` scans `voxel_data`.** When removing the lowest
  cell in a column, we re-scan the entire `voxel_data` dictionary. For up to
  ~10k tracked cells this is fast; if the tracked set grows large, replace
  with a per-column ordered set.
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
