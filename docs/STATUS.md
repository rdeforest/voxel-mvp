# Project Status

> **Maintenance contract:** the "Resumption Brief" must reflect the current
> moment. The "Tracker" below it can drift a little. If updating this doc
> after a session takes more than ten minutes, it's too big — shrink it.

---

## Resumption Brief

*Last updated: end of building system + Part registry refactor session*

**Where you are:** Phase 5 building system is partially implemented and the
codebase has had a full cleanup pass. The wooden board Part exists and can be
placed, rotated (KEY_R), and removed (TAB to Remove mode). A thorough code
review found 14 issues; all were addressed. The structural integrity system was
then refactored to track Parts separately from terrain voxels (`part_registry`
with `PartData` inner class, `_cell_to_part` reverse map, `_tick_part_strain`
per-frame collapse check).

**Pick up here, in this order:**

1. **Test board collapse and removal after the part_registry refactor.** Both
   were buggy before; the refactor was the principled fix. Dig terrain from
   under a board and wait 3 seconds — it should fall as a RigidBody3D. Remove
   mode should work on all boards now (no more "stuck" boards from overlapping
   footprints).

2. **If those work, next building milestone:** decide whether to add more Part
   types, add SDF seam matching (Option A2 — boards write SDF into their cells
   so terrain mesh blends cleanly), or tackle snap points. The design for all
   three exists; nothing is started.

3. **Debug visuals for Parts are unimplemented.** Currently only terrain voxels
   get colored cubes. Part strain (the 3-second window) is invisible. Low
   priority but useful for testing.

**Active mental state to preserve:** The Part registry split means `voxel_data`
is now terrain-only. Parts have `PartData` (typed inner class on
`StructuralIntegrity`) with `cells: Array[Vector3i]` and `material: Materials`.
Part support is checked fresh every frame in `_tick_part_strain` — no dirty
queue for Parts. Part collapse materializes as a RigidBody3D in `_collapse_part`
(inside SI, not CollapseDetector). CollapseDetector now handles terrain only.

---

## Tracker

### v0.0 — Phase status

| Phase | State | Notes |
|-------|-------|-------|
| 5 — Building System | In progress | Board Part works (place/rotate/remove); collapse needs post-refactor test; SDF seam, snap points, more Parts unstarted |

### Bugs

| ID | State | Notes |
|----|-------|-------|
| 2c | Closed | Player fall-through fixed via `Action.validate()` refusal in Fill/Flatten |
| 2a | Deferred | Flatten clears only one sheet above — cosmetic; deferred until building replaces flatten |

### Phase 5 design decisions worth not re-litigating

- **Hybrid prefab approach (Option A2).** Prefabs occupy voxel cells via
  metadata; they write matching SDF samples into their cells so the
  Transvoxel mesher produces a clean surface continuous with surrounding
  terrain, while the prefab's static mesh renders the engineered geometry.
  Costs are paid at placement / chunk-remesh time, not per-frame.
- **Axis-aligned footprints, 90° rotation.** Rotated prefabs are a v0.9+
  problem; the axis-aligned restriction keeps SDF-matching tractable.
- **Refuse-don't-deform.** Both terrain ops and prefab placements refuse
  when constraints can't be satisfied, rather than silently adjusting.
- **Action-as-data.** Every world-modifying op routes through `Action`.
- **Targeting lives at the call site (the EditMode `make_action` callable),
  not inside the Action.** Actions take final, computed parameters.
- **Schematic format: `.tres` resource, optional `.tscn` for scene-graph
  content.** Editor-friendly, serializable, diff-able.
- **Cell footprint authoring: computed from mesh bounds by default, with
  optional hand-override.**
- **Snap points are per-Schematic metadata, hand-authored.** Match-time
  Joint creation is a v0.1 follow-on; data structure present, UI deferred.
- **Parts tracked at Part level, not voxel level.** `part_registry`
  (Node3D → PartData) separate from `voxel_data` (terrain only). Part
  support checked fresh each frame; no dirty queue for Parts.

### Deferred but tracked

| Item | Where it goes | Why deferred |
|------|---------------|--------------|
| Per-material strain duration (`STRAIN_DURATION_SEC` reads from `Materials`) | v0.1 polish | Flat 3.0s is fine for v0.0 |
| Nature-of-change reset scaling | v0.1 polish | Flat `STRAIN_RESET_SEC = 2.7` works |
| Surface-geometry pulse (strain feedback on terrain mesh, not debug cubes) | v0.2 art pass | Real shader work |
| Part strain debug visualization | Soon | Part strain window currently invisible; useful for testing |
| Material fatigue (cumulative strain history) | v0.9 survival | Only meaningful once mobs exist |
| Hinge-at-boundary collapse (towers tip rather than lift off) | v0.1 polish | Wait for real scenarios to tune against |
| Generic `Propagator` extraction | When second use case appears | One customer isn't enough to generalize |
| Mid-break prefab destruction | v0.1 polish | Whole-prefab destruction works for Phase 5 |
| Non-adjacent linkages (ropes, cables) | Late Phase 5 or v0.1 | Adjacency-based support is free; cross-space needs new data structure |
| Load propagation (top-down paired with support) | v0.1 | Same algorithm reversed |
| SDF seam matching (Option A2) | Phase 5 ongoing | Boards write SDF into their cells; design done, implementation unstarted |
| Snap points UI | Phase 5 ongoing | Data structure present, UI deferred |
| In-game Schematic editor | v0.9+ | Hand-author Schematics for Phase 5 |
| `WorldContext` parameter object | When 5+ Actions share same refs | Verbose-but-explicit constructors until then |
| `VoxelRecord` typed class for `voxel_data` | When part_registry pattern proves itself | Same inner-class approach as PartData |

### Known limits (recorded, not fixed)

- **`_resume_unfinished_floods` budget starvation:** components larger than
  `DETECTION_BUDGET` (500 voxels) take multiple settled frames to fully
  detect. Not a correctness bug, just lag. Fix is budget profiling, deferred.
- **`PLAYER_CLEARANCE` in Fill/Flatten is a guess (1.0m).** Tune if refusals
  fire too eagerly or fall-through reappears.
- **Part scene layout is assumed (flat children).** `_collapse_part` calls
  `get_children()` expecting a flat list of MeshInstance3D + CollisionShape3D.
  Works for board.tscn; will break silently for nested scenes. Not enforced
  anywhere in `Part` or `Schematic`. Document or validate before adding new
  Part types.
- **`FlattenAction` center/plane-point asymmetry.** Bounding box is offset
  inward but the plane runs through the surface hit. Both are explicit
  constructor parameters with a comment; easy to change if it becomes a bug.

### Architectural decisions worth not re-litigating

- **Track Godot stable, not master.** Pin to `4.6-stable` (`89cea1439`).
- **Double-precision godot_voxel build from day one.**
- **No engine forks.**
- **`godot/modules/voxel` symlink, not `custom_modules`.**
- **Worklist-fixpoint propagation is one customer, not generalized.**
- **Signals (not a custom event bus) for `voxel_support_increased`.**
- **Strain timer accumulated against physics `delta`, not wall-clock.**
- **Action-as-data. Targeting at the call site.**
- **Parts separate from terrain voxels in SI. Part support checked per-frame.**

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
