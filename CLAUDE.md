# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Run

**Prerequisites:** `git`, `scons`, `python3`, and a C/C++ compiler. The Godot and godot_voxel repos must exist as siblings of this project at the paths in `tools/versions.env`:

```
tools/build            # build Godot + godot_voxel (idempotent, stamp-checked)
bin/godot              # launch the built editor/game (pass Godot args directly)
bin/godot --path . -e  # open this project in the editor
```

`tools/build` pins both repos to `tools/versions.env` (Godot `89cea1439` = 4.6-stable, godot_voxel `v1.6`), wires the `godot/modules/voxel` symlink, and skips the SCons build when the stamp matches.

**Run tests (GUT):**

```
bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/
```

To run a single test file:

```
bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/ -gselect=test_gut_example.gd
```

Tests can also be run interactively from the GUT panel inside the editor.

## Architecture

This is a Godot 4.6 game built with **double-precision** (`precision=double` — cannot be removed; it's compiled into the engine binary for planet-scale coordinates) and the **godot_voxel** module (Transvoxel SDF meshing).

### Scene graph

```
world.tscn
├── VoxelLodTerrain      ← procedural SDF terrain
├── StructuralIntegrity  ← Node; facade composing the structural subsystem
└── Player (CharacterBody3D)
    ├── Head / Camera3D
    ├── RayCast3D
    └── EditPreview (MeshInstance3D)
```

`player.gd` acquires `StructuralIntegrity` and `VoxelLodTerrain` via `get_parent().get_node()` in `_ready`.

### Action pattern (`scripts/actions/`)

Every world-modifying operation is an `Action` (`RefCounted`):

```gdscript
action.validate() -> bool   # refuses if constraints can't be satisfied
action.execute()  -> void   # performs the operation
```

`EditMode` (`scripts/edit_mode.gd`) is a data object holding callables for one editing mode (Dig, Fill, Flatten, Build, Remove). The `EditModeCatalog` (`scenes/player/edit_mode_catalog.gd`) builds the array of EditModes at player startup, wiring each one's `make_action` callable to an `ActionFactories` (`scenes/player/action_factories.gd`) method. When the player clicks, `player.gd:_try_edit_terrain` calls `current_mode().make_action.call(hit_pos, hit_normal)`, then `validate()` → `execute()`. Targeting logic (raycasting, computing sphere centers, build placement snap) lives inside `ActionFactories`, not inside the Action itself.

New Actions: extend `Action`, implement `validate()` and `execute()`, add a `make_*` factory to `ActionFactories`, and a new `EditMode` entry in `EditModeCatalog._build_catalog()`.

### Structural integrity system

**`StructuralIntegrity`** (`scripts/structural_integrity.gd`) is a `Node` facade. It composes three `RefCounted` components plus a peer `CollapseDetector`:

```
StructuralIntegrity (Node, facade)
├── terrain_support: TerrainSupport     ← voxel_data, propagation, signal
├── part_support:    PartSupport        ← part_registry, strain, collapse
├── debug:           IntegrityDebug     ← debug cubes
└── _collapse_detector: CollapseDetector (peer of terrain_support)
```

The facade owns `_physics_process` orchestration and `wake_falling_bodies` (which needs scene-tree access). All other state lives on the components.

**`TerrainSupport`** (`scripts/structural/terrain_support.gd`) owns `voxel_data: Dictionary[Vector3i, VoxelRecord]`, `dirty_queue`, and `_lowest_registered_y`. A worklist fixpoint drains `dirty_queue` (FIFO, BFS-order) at `PROPAGATION_BUDGET` (200) cells per physics frame via `process_dirty_queue()`. `is_natural_terrain(pos)` requires both untracked-solid AND bedrock — the combination grants `FULL_SUPPORT` to neighbours.

Classification cascade in `_support_from_neighbor` (priority order): tracked voxel → part-occupied → solid-above (skip) → solid-bedrock (FULL) → suspended-mass (lazy-register, skip) → air (skip).

Emits `voxel_support_increased` when a voxel's recalculated support is meaningfully higher. `CollapseDetector` listens (it's wired in its `_init` taking `TerrainSupport` directly).

**`PartSupport`** (`scripts/structural/part_support.gd`) owns `part_registry: Dictionary[Node3D, PartData]`, `_cell_to_part`, `_part_strain`, `_hovered_part`. Part support is recomputed fresh each physics frame in `tick_strain(delta, pulse)`: sort parts ascending by `placement_y`, then for each part find its **direct supporter** (the part with the highest `placement_y < mine` in the part's own cell or the cell below). Direct terrain contact short-circuits to `FULL_SUPPORT`. Tall parts (multi-cell Y span from non-Y rotation) only check support from the bottom row of footprint cells (`_min_y(cells)`).

`PartData.in_limbo` is true when any dependency hasn't settled. `tick_strain` skips strain accumulation while in-limbo.

When strain expires, `_collapse_part` reparents the part's children to a new `RigidBody3D` (`continuous_cd = true`). Visual: `_apply_visual` puts the strain color on `emission` so the part's natural surface color stays visible.

**`CollapseDetector`** (`scripts/collapse_detector.gd`) handles *terrain* collapses. Flood-fills connected components of unsupported terrain voxels into pending collapses, runs the strain timer, and on expiry hands the voxels to `FallingBodyFactory.from_voxels()` (`scripts/structural/falling_body_factory.gd`) — which greedy-merges them into axis-aligned boxes and returns a `RigidBody3D`. The detector then carves the cells out of the SDF.

Typed records (all `RefCounted`, in `scripts/structural/`):
- `VoxelRecord` — `{support, material, dirty}` for tracked voxels.
- `PartData` — `{cells, material, placement_y, support, in_limbo}` for placed parts.
- `PendingCollapse` — `{voxels, voxel_set, strained}` for in-progress collapses.
- `PendingFlood` — `{voxels, frontier, visited}` for in-progress flood-fills.

**Cycle prevention.** `TerrainSupport` and `PartSupport` hold typed back-references to each other; the facade calls `terrain_support.bind_part_support(null)` in `_exit_tree` to break the cycle so the RefCounted components can free. The `bind_part_support` parameter is untyped because it must accept `null`.

Detailed mechanism rationale (in-limbo, lazy-expansion bounds, strain rewind, pause-correct delta accumulation, etc.) lives in `docs/architecture.md`. The doc complements `roadmap.md → Architectural Commitments` (design-level decisions) and this file (where the code lives).

### Player composition (`scenes/player/`)

`player.gd` (a `CharacterBody3D` Node) composes five `RefCounted` helpers:

- `PlayerMovement` (`movement.gd`) — gravity, jump, WASD via `tick(delta)`.
- `CameraRig` (`camera_rig.gd`) — mouse motion, head/body rotation.
- `BuildState` (`build_state.gd`) — selected part, material, rotation. Emits `changed()` so the mode label updates.
- `ActionFactories` (`action_factories.gd`) — `make_dig/fill/flatten/construction/removal` plus `get_flatten_normal`. Holds `EDIT_RADIUS` const.
- `EditModeCatalog` (`edit_mode_catalog.gd`) — builds the EditMode array at startup, wiring factory callbacks. Lambdas inside `_build_catalog` deliberately close over local parameters (`af`, `bs`) and local mesh/material vars rather than `self`, to avoid catalog ↔ Callable cycles that would leak meshes at exit.

`player.gd` keeps: `@onready` node references, input dispatch dicts (`_key_actions`, `_mouse_button_actions`), `_process` hover detection, `_physics_process` movement delegation, `_try_edit_terrain`, and mode UI (label update, cycle, wireframe/debug toggles, quit).

### Parts (`scripts/schematics/`, `assets/parts/`)

`Schematic` (base, `Resource`) carries an optional hand-authored footprint and snap_points (UI deferred). `Part` extends it with `dimensions: Vector3`, `material_name: StringName`, and an optional `scene: PackedScene` override. `Part.instantiate()` returns a Node3D — either the scene if set, or a procedural `StaticBody3D` with MeshInstance3D + CollisionShape3D sized by `dimensions`, albedo from `Materials.from_name(material_name).albedo`. Bottom-anchored at local Y=0.

Current catalog (`assets/parts/<name>/<name>.tres`): board, plank, stud, beam — all parametric rectangular Parts that differ only in `dimensions`. Adding a new wood Part is a one-line `.tres`.

Multi-axis rotation: `ConstructionAction.rotation: Vector3i` (0–3 per axis). Rotation is around the body's local origin (the unrotated bottom-center); after rotation, the instance is shifted so the rotated bottom lands at `placement_pos.y` and the rotated horizontal centroid sits over `placement_pos.x/.z`. Use `Transform3D(basis, Vector3.ZERO) * aabb` for AABB rotation (Godot doesn't define `Basis * AABB`).

**Placement snap:** `_make_construction_action` snaps `placement_pos.y = floor(hit_pos.y)`. Parts always sit on cell Y-boundaries — avoids the "click on a slope, part floats above the surface" case where XZ rounding moved the placement away from the actual hit surface.

Player controls in Build mode: `[`/`]` cycle parts, `R` rotates around Y, `T` rotates around X, `Y` rotates around Z, `M` cycles material.

### Materials

`Materials` (`scripts/materials.gd`) is a `Resource` subclass with `@export` fields (`decay`, `albedo`, `angle_of_repose`, `failure_mode`). Data lives in `assets/materials/<name>.tres`; the class exposes static singleton accessors (`Materials.STONE`, etc.) that lazy-load via `load("res://assets/materials/...")`. `Materials.from_name(StringName)` resolves a Part's `material_name` to the singleton, falling back to STONE for unknown names.

### SDF conventions

- Negative SDF = inside solid; positive = air. Surface at zero-crossing.
- Use `SDF_AIR = 5.0` (not 1.0) to clear voxels — Transvoxel interpolation pulls the surface back toward solid neighbours unless the value is large enough.
- Use `SDF_SOLID_THRESHOLD = 0.0` to test solidity in queries.
- All SDF and structural constants live in `VoxelConstants` (`scripts/voxel_constants.gd`).

### Key conventions

- **Refuse-don't-deform.** Actions refuse via `validate()` when constraints can't be met. `FillAction` extends this to physics state via `intersect_shape` — fills that would overlap a `RigidBody3D` are refused. `ConstructionAction.validate` accepts a footprint cell as valid attachment if it directly intersects an existing part (intersection placement); welding/joining to make that mutual is v0.1.
- **Input dispatch via dictionary lookup.** `_key_actions` and `_mouse_button_actions` map keycodes/buttons to callables; no if-chains.
- **`PLAYER_CLEARANCE = 1.0m`** in `FillAction` and `FlattenAction` prevents filling the player's occupied space.
- **Signal locality.** `voxel_support_increased` lives on `TerrainSupport`, not the facade — it's emitted from terrain propagation, and `CollapseDetector` listens directly via its `_terrain_support` reference.
- **Strain timer accumulates against physics `delta`** (not wall-clock), so it pauses correctly when the tree is paused.
- **`wake_falling_bodies()`** runs on every `notify_terrain_changed` and `remove_part` — SDF terrain edits don't signal contact-change to the physics engine, so resting `RigidBody3D`s need an explicit nudge.
- **Typed dicts (`Dictionary[K, V]`)** for `part_registry`, `voxel_data`, `_voxel_to_pending`. Plain `Dictionary` poisons inferred types from iteration (`for x in dict` makes `x` Variant).
- **Helper lambdas capture local refs, not `self`.** When a `RefCounted` class holds an `Array[Callable]` whose Callables reference instance fields, the implicit `self` capture forms a cycle. Pass dependencies as parameters and let lambdas close over the locals. See `EditModeCatalog._build_catalog` for the pattern.
- **Cycle break in `_exit_tree`.** `StructuralIntegrity._exit_tree` calls `terrain_support.bind_part_support(null)` to break the `TerrainSupport ↔ PartSupport` reference cycle.

## Project State

See `docs/STATUS.md` for the current resumption brief and `docs/roadmap.md` for the version strategy. The status doc is the authoritative "where are we and what's next."
