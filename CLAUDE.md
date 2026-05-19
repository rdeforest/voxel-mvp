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
├── StructuralIntegrity  ← node; manages support propagation and collapse
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

`EditMode` (`scripts/edit_mode.gd`) is a data object holding callables. The player builds an array of `EditMode` instances in `_ready()` using a builder chain. When the player clicks, `player.gd:_try_edit_terrain` calls `current_mode().make_action.call(hit_pos, hit_normal)`, then `validate()` → `execute()`. Targeting logic (raycasting, computing sphere center) stays at the call site in the player's action factory methods, not inside the Action.

New Actions: extend `Action`, implement `validate()` and `execute()`, add a factory method to `player.gd`, and a new `EditMode` entry in `_ready()`.

### Structural integrity system

**`StructuralIntegrity`** (`scripts/structural_integrity.gd`) runs two parallel support systems:

**Terrain voxels** live in `voxel_data: Dictionary`. A worklist fixpoint drains `dirty_queue` (FIFO via `pop_front`, BFS-order) at `PROPAGATION_BUDGET` (200) cells per physics frame. `_lowest_registered_y: Dictionary[Vector2i, int]` indexes the lowest registered Y per `(x, z)` column; `_is_bedrock(pos)` returns true when the column has nothing registered below `pos.y`. `_is_natural_terrain` requires both untracked-solid AND bedrock — the combination is what grants FULL_SUPPORT to neighbours.

**Lazy expansion.** `_calculate_support` only blesses an untracked-solid neighbour as FULL_SUPPORT if it's bedrock; non-bedrock untracked solid gets lazy-registered with material STONE so propagation can compute its actual support. Lazy registration only fires when the current cell's support is itself above `FALL_THRESHOLD` — cells already at zero won't seed a chain worth extending. The result: every dig creates an initial 1-cell shell, then propagation extends the tracked region outward through structurally-relevant rock until support saturates to zero. Cascade depth = material decay budget (~20 cells for STONE).

When a voxel's support increases meaningfully, it emits `voxel_support_increased` so CollapseDetector can rewind any pending strain timer.

**Placed Parts** live in `part_registry: Dictionary[Node3D, PartData]`. `PartData` (inner class) holds `cells: Array[Vector3i]`, `material: Materials`, `placement_y: float` (world Y of the bottom face), and a recomputed `support: float`. A reverse map `_cell_to_part: Dictionary[Vector3i, Array[Node3D]]` is a per-cell **stack** — multiple thin parts can share one voxel cell when stacked vertically, ordered by `placement_y`.

Part support is recomputed fresh each frame by `_recompute_part_support()`: sort parts ascending by `placement_y`, then for each part find its **direct supporter** (the part with the highest `placement_y < mine` in the part's own cell or the cell below). Support value = `max(supporter_support) - material.decay`. Direct terrain contact short-circuits to `FULL_SUPPORT`. Tall parts (multi-cell Y span from non-Y rotation) only check support from the bottom row of footprint cells.

`PartData.in_limbo` is true when any of the part's support dependencies — a supporter Part still in-limbo or a terrain voxel still dirty — hasn't settled. `_tick_part_strain` skips strain accumulation while in_limbo, so a transient zero during propagation doesn't trigger a 3-second countdown.

Strain accumulates against physics `delta` when `support <= FALL_THRESHOLD`. On expiry, `_collapse_part` reparents the part's children to a new `RigidBody3D` with `continuous_cd = true` (so thin boards don't tunnel through terrain). Visual: `_apply_part_visual` puts the strain color on `emission` rather than replacing the albedo, so the part's natural surface color (and future textures) stays visible.

**`CollapseDetector`** (`scripts/collapse_detector.gd`) handles *terrain* collapses only. Flood-fills connected components of unsupported terrain voxels into pending collapses, runs the same strain timer, then on expiry extracts the cells from the SDF and materialises them as a falling RigidBody3D (greedy box merge for collision).

### Parts (`scripts/schematics/`, `assets/parts/`)

`Schematic` (base, `Resource`) carries an optional hand-authored footprint and snap_points (UI deferred). `Part` extends it with `dimensions: Vector3`, `material_name: StringName`, and an optional `scene: PackedScene` override. `Part.instantiate()` returns a Node3D — either the scene if set, or a procedural `StaticBody3D` with MeshInstance3D + CollisionShape3D sized by `dimensions`, albedo from `Materials.from_name(material_name).albedo`. Bottom-anchored at local Y=0.

Current catalog (`assets/parts/<name>/<name>.tres`): board, plank, stud, beam — all parametric rectangular Parts that differ only in `dimensions`. Adding a new wood Part is a one-line `.tres`.

Multi-axis rotation: `ConstructionAction.rotation: Vector3i` (0–3 per axis). Rotation is around the body's local origin (the unrotated bottom-center); after rotation, the instance is shifted so the rotated bottom lands at `placement_pos.y` and the rotated horizontal centroid sits over `placement_pos.x/.z`. Use `Transform3D(basis, Vector3.ZERO) * aabb` for AABB rotation (Godot doesn't define `Basis * AABB`).

Player controls in Build mode: `[`/`]` cycle parts, `R` rotates around Y, `T` rotates around X, `Y` rotates around Z.

### Materials

`Materials` (`scripts/materials.gd`) is a class with static singleton instances (`Materials.STONE`, `Materials.WOOD`, etc.). Each carries `decay` (support loss per hop), `albedo: Color` (used by the procedural Part build), `angle_of_repose`, and `failure_mode`. `Materials.from_name(StringName)` resolves a Part's `material_name` to the singleton.

### SDF conventions

- Negative SDF = inside solid; positive = air. Surface at zero-crossing.
- Use `SDF_AIR = 5.0` (not 1.0) to clear voxels — Transvoxel interpolation pulls the surface back toward solid neighbors unless the value is large enough.
- Use `SDF_SOLID_THRESHOLD = 0.0` to test solidity in queries.
- All SDF and structural constants live in `VoxelConstants` (`scripts/voxel_constants.gd`).

### Key conventions

- **Refuse-don't-deform.** Actions refuse via `validate()` when constraints can't be met rather than silently adjusting. Extended to physics state via `FillAction`'s `direct_space_state.intersect_shape` check — fills that would overlap a `RigidBody3D` are refused (otherwise the body squirts through the world).
- **Input dispatch via dictionary lookup.** `player.gd` maps keycodes and mouse buttons to callables; no if-chains.
- **`PLAYER_CLEARANCE = 1.0m`** in `FillAction` and `FlattenAction` prevents filling the player's occupied space. Tune if the player `CapsuleShape3D` dimensions change.
- Signals (not an event bus) connect `StructuralIntegrity` → `CollapseDetector` for `voxel_support_increased`.
- Strain timer accumulates against physics `delta` (not wall-clock), so it pauses correctly when the game tree is paused.
- **`_wake_falling_bodies()`** on every `notify_terrain_changed` and `remove_part` — SDF terrain edits don't signal contact-change to the physics engine, so resting RigidBody3Ds need an explicit nudge when the ground under them changes.
- **Typed dicts (`Dictionary[K, V]`, Godot 4.4+)** for `part_registry`. Plain `Dictionary` poisons inferred types from iteration (`for x in dict` makes `x` Variant, breaking `==` inference). Use typed dicts when iteration variable types matter.

## Project State

See `docs/STATUS.md` for the current resumption brief and `docs/roadmap.md` for the version strategy. The status doc is the authoritative "where are we and what's next."
