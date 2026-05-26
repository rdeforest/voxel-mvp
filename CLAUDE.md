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

`EditMode` (`scripts/edit_mode.gd`) is a data object holding callables for one *activity* (Dig, Build, etc.). Activities are grouped under `Tool`s (`scripts/tool.gd`) — three of them today: **None**, **Landscape**, **Construction**. The `ToolCatalog` (`scenes/player/tool_catalog.gd`) builds the tool array at player startup, wiring each activity's `make_action` callable to an `ActionFactories` (`scenes/player/action_factories.gd`) method.

Input: **Tab** cycles tools; **1..9** picks an activity within the current tool; each tool remembers its last activity. When the player clicks, `player.gd:_try_edit_terrain` calls `current_activity().make_action.call(hit_pos, hit_normal)`, then `validate()` → `execute()`. Targeting logic (raycasting, sphere centers, build placement) lives inside `ActionFactories`, not inside the Action itself.

New Actions: extend `Action`, implement `validate()` / `execute()` / `preview()`, add a `make_*` factory to `ActionFactories`, and a new `EditMode` entry under the appropriate tool in `ToolCatalog._build_catalog()`.

### Event bus (`scripts/events/`)

Two identifiers refer to the same thing for different purposes:
- **`VoxelEventBusSingleton`** — the autoload instance (registered in `project.godot`). Use this at call sites.
- **`VoxelEventBusType`** — the `class_name` of the script. Use this in type hints. Godot 4 forbids the class_name from matching any autoload name, hence the `Type` / `Singleton` suffixes; the prefix `Voxel` is part of the name because the bus has voxel-space spatial filtering, not just plain pub/sub.

Spatial pub/sub: subscribers register per-cell or channel-wide interest; the bus dispatches each emitted event to overlapping subscribers.

API:
```gdscript
VoxelEventBusSingleton.subscribe_cell(channel, cell, callback)
VoxelEventBusSingleton.subscribe(channel, callback)          # channel-wide
VoxelEventBusSingleton.emit(channel, event)
# matching unsubscribe_cell / unsubscribe (only needed for intentional cancel)
```

Channel taxonomy (`scripts/events/*_event.gd`):
- **Primitive** (emitted by actions): `terrain_sdf_changed`, `voxel_added`, `voxel_removed`, `part_added`, `part_removed`.
- **Derived** (emitted by integrity components): `voxel_support_changed`, `region_collapsing`, `part_support_changed` (reserved).

Each event extends `VoxelEvent { grid_id, cells }`. `cells` is the dispatch footprint — the bus indexes per-cell subscribers against it. `grid_id` is in every payload from day one so multi-grid (Phase 5.5d, deferred) lands without payload churn.

**Lifetime: WeakRef.** Each subscription stores `WeakRef(owner) + method name`, not the bare `Callable`. When the subscriber is freed (Node `queue_free`, or RefCounted refcount-to-zero), the WeakRef goes null and the bus prunes lazily on next emit. **No `dispose()` calls required.** Subscribers can be created and forgotten.

**Caveat:** subscribe with a bound method (`self.my_method`), not an anonymous lambda. Lambdas have no Object to weakref and would persist until manually unsubscribed.

### Structural integrity system

**`StructuralIntegrity`** (`scripts/structural_integrity.gd`) is a `Node` facade. It composes three `RefCounted` components plus a peer `CollapseDetector`:

```
StructuralIntegrity (Node, facade)
├── terrain_support: TerrainSupport     ← voxel_data, propagation
├── part_support:    PartSupport        ← part_registry, strain, collapse
├── debug:           IntegrityDebug     ← debug cubes
└── _collapse_detector: CollapseDetector (peer of terrain_support)
```

The facade owns `_physics_process` orchestration, `wake_falling_bodies` (which needs scene-tree access), and `is_quiescent` (for save gating). All other state lives on the components. Mutations come through the bus; the facade only exposes **queries** (`get_support`, `has_part`, `has_part_cell`) and one UI hook (`set_debug_visuals_enabled`). The bus is subscribed in `_ready` for `terrain_sdf_changed` + `part_removed` so the facade can call `wake_falling_bodies` when the world changes.

**`TerrainSupport`** (`scripts/structural/terrain_support.gd`) owns `voxel_data: Dictionary[Vector3i, VoxelRecord]`, `dirty_queue`, and `_lowest_registered_y`. Subscribes channel-wide in `_init` to `voxel_added`, `voxel_removed`, and `terrain_sdf_changed`. A worklist fixpoint drains `dirty_queue` (FIFO, BFS-order) at `PROPAGATION_BUDGET` (200) cells per physics frame via `process_dirty_queue()`. `is_natural_terrain(pos)` requires both untracked-solid AND bedrock — the combination grants `FULL_SUPPORT` to neighbours.

Classification cascade in `_support_from_neighbor` (priority order): tracked voxel → part-occupied → solid-above (skip) → solid-bedrock (FULL) → suspended-mass (lazy-register, skip) → air (skip).

Emits `voxel_support_changed` via the bus when a voxel's recalculated support changes meaningfully. `CollapseDetector` subscribes and uses the event for strain-rewind on support increases.

**`PartSupport`** (`scripts/structural/part_support.gd`) owns `part_registry: Dictionary[Node3D, PartData]`, `_cell_to_part`, `_part_strain`. Part support is recomputed fresh each physics frame in `tick_strain(delta, pulse)`: sort parts ascending by `placement_y`, then for each part find its **direct supporter** (the part with the highest `placement_y < mine` in the part's own cell or the cell below). Direct terrain contact short-circuits to `FULL_SUPPORT`. Tall parts (multi-cell Y span from non-Y rotation) only check support from the bottom row of footprint cells (`_min_y(cells)`). Holds a `raycast` reference (set by player); stress emission only renders when the cursor is within 6m of a part's cells *or* its support has fallen below 0.30 (orange tier).

`PartData.in_limbo` is true when any dependency hasn't settled. `tick_strain` skips strain accumulation while in-limbo.

When strain expires, `_collapse_part` reparents the part's children to a new `RigidBody3D` (`continuous_cd = true`). Visual: `_apply_visual` puts the strain color on `emission` so the part's natural surface color stays visible.

**`CollapseDetector`** (`scripts/collapse_detector.gd`) handles *terrain* collapses. Flood-fills connected components of unsupported terrain voxels into pending collapses, runs the strain timer, and on expiry hands the voxels to `FallingBodyFactory.from_voxels()` (`scripts/structural/falling_body_factory.gd`) — which greedy-merges them into axis-aligned boxes and returns a `RigidBody3D`. The detector then carves the cells out of the SDF.

**Falling body lifecycle.** `FallingBodyFactory` stashes `cell_offsets` (each origin cell's local-space offset from the body's centroid at collapse time) on the body via `set_meta`. `StructuralIntegrity._tick_falling_bodies()` runs every physics frame: for each body with `cell_offsets`, sample SDF at each cell's current world position (via `body.global_transform * offset`):
- **All cells in solid SDF (fully buried)** → emit `voxel_added` per cell at its current world-cell, free the body. The fallen mass becomes tracked SDF terrain.
- **Some cells in solid (partially buried)** → `body.freeze = true`. Body locks in place; physics stops simulating it.
- **No cells in solid (free)** → leave alone; physics handles it (sleeps when at rest). If the body was previously frozen and is now free (e.g., player dug terrain out from around it), unfreeze and wake.

`FillAction.execute` freezes any overlapping `RigidBody3D` **before** mutating SDF, so the next physics tick doesn't squirt the body sideways from the collision overlap. The classifier integrates them on subsequent ticks.

Typed records (all `RefCounted`, in `scripts/structural/`):
- `VoxelRecord` — `{support, material, dirty}` for tracked voxels.
- `PartData` — `{cells, material, placement_y, support, in_limbo}` for placed parts.
- `PendingCollapse` — `{voxels, voxel_set, strained}` for in-progress collapses.
- `PendingFlood` — `{voxels, frontier, visited}` for in-progress flood-fills.

**Cycle prevention.** `TerrainSupport` and `PartSupport` hold typed back-references to each other; the facade calls `terrain_support.bind_part_support(null)` in `_exit_tree` to break the cycle so the RefCounted components can free. The `bind_part_support` parameter is untyped because it must accept `null`.

Detailed mechanism rationale (in-limbo, lazy-expansion bounds, strain rewind, pause-correct delta accumulation, etc.) lives in `docs/architecture.md`. The doc complements `roadmap.md → Architectural Commitments` (design-level decisions) and this file (where the code lives).

### Player composition (`scenes/player/`)

`player.gd` (a `CharacterBody3D` Node) composes five `RefCounted` helpers:

- `PlayerMovement` (`movement.gd`) — gravity, jump, WASD via `tick(delta)`. Shift suppresses horizontal movement (chord modifier).
- `CameraRig` (`camera_rig.gd`) — mouse motion, head/body rotation.
- `BuildState` (`build_state.gd`) — selected part, material, rotation, `placement_offset`. Emits `changed()` so the HUD label updates.
- `ActionFactories` (`action_factories.gd`) — one `make_*` per activity (probe, dig, fill, flatten, raise, lower, fill_voxel, empty_voxel, construction, removal). Holds `EDIT_RADIUS`.
- `ToolCatalog` (`tool_catalog.gd`) — builds the `Tool` array (None / Landscape / Construction), each tool holding its activity `EditMode`s. Lambdas inside `_build_catalog` close over local parameters (`af`, `bs`) rather than `self`, to avoid catalog ↔ Callable cycles that would leak meshes at exit.

`player.gd` state: `tool_index: int` plus `_activity_indices: Array[int]` (one per tool — last-activity memory). `current_tool()` and `current_activity()` are the accessors. Input dispatch dicts (`_key_actions`, `_mouse_button_actions`) and `_handle_placement_wheel` route Shift+W/A/E + wheel into `build_state.adjust_offset` for free part placement.

### Parts (`scripts/schematics/`, `assets/parts/`)

`Schematic` (base, `Resource`) carries an optional hand-authored footprint and snap_points (UI deferred). `Part` extends it with `dimensions: Vector3`, `material_name: StringName`, and an optional `scene: PackedScene` override. `Part.instantiate()` returns a Node3D — either the scene if set, or a procedural `StaticBody3D` with MeshInstance3D + CollisionShape3D sized by `dimensions`, albedo from `Materials.from_name(material_name).albedo`. Bottom-anchored at local Y=0.

Current catalog (`assets/parts/<name>/<name>.tres`): board, plank, stud, beam — all parametric rectangular Parts that differ only in `dimensions`. Adding a new wood Part is a one-line `.tres`.

Multi-axis rotation: `ConstructionAction.rotation: Vector3i` (0–3 per axis). Rotation is around the body's local origin (the unrotated bottom-center); after rotation, the instance is shifted so the rotated bottom lands at `placement_pos.y` and the rotated horizontal centroid sits over `placement_pos.x/.z`. Use `Transform3D(basis, Vector3.ZERO) * aabb` for AABB rotation (Godot doesn't define `Basis * AABB`).

**Placement is free** along all three axes — `ConstructionAction.placement_pos = hit_pos + BuildState.placement_offset`. The offset accumulates from Shift+W/A/E + wheel ticks (camera-relative axes, WHEEL_STEP = 0.05m). The offset resets on each successful placement and on tool cycle.

Player controls in **Construction → Build** activity: `[`/`]` cycle parts, `R/T/Y` rotate around Y/X/Z, `M` cycles material, Shift+W/A/E + wheel adjusts offset. Shift+key always suppresses the underlying WASD movement key — Shift+W is a distinct input from W, not "walk + something."

**Debug overlays:**
- `V` toggles the stress overlay (`IntegrityDebug`). Two-pass renderer: visible-pass wireframe outlines (depth-tested), obscured-pass corner-bracket markers (no depth test, off until `H`). Cells with `support > 0.30` only render within 6m of the raycast hit; cells `≤ 0.30` always render so failures are never hidden.
- `H` toggles the obscured-pass corner markers (only visible with `V` on).
- `G` toggles the voxel grid overlay (wireframes the targeted cell and its Chebyshev neighborhood, helpful for understanding voxel boundaries during flatten/dig/fill).
- `F` toggles full-scene wireframe.

**Action preview rendering:** Every `Action` subclass implements `preview() -> ActionPreview`, returning the cells it would change classified by intent (`air`, `solid`, `part`) plus a `refused` flag. The world-space `VoxelPreviewRenderer` (`scenes/player/voxel_preview_renderer.gd`) builds an Action each frame from the current raycast hit, calls `preview()`, and draws the cells via two ImmediateMesh passes (visible / obscured). Outlines inset 0.05 to avoid z-fighting with the Transvoxel surface. Refusal lerps intent colors toward grey. The legacy idealised sphere/plane previews are gone for Dig/Fill/Flatten; Build keeps its part-mesh ghost.

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
- **Mutations go through the bus.** Actions emit primitive events (`terrain_sdf_changed`, `voxel_added`, etc.); they don't call `StructuralIntegrity` directly for state changes. Queries (`has_part_cell`, `has_part`) still call the facade — they're synchronous validation, not notification.
- **Subscribe with bound methods, not lambdas.** `self.my_handler` lets the bus weakref the owner and auto-clean. `func(e): handle(e)` has no Object to weakref and would leak until manually unsubscribed.
- **Wake-on-mutate.** `wake_falling_bodies()` is bus-triggered: `StructuralIntegrity` subscribes to `terrain_sdf_changed` and `part_removed`. SDF terrain edits don't signal contact-change to the physics engine, so resting `RigidBody3D`s need an explicit nudge.
- **Strain timer accumulates against physics `delta`** (not wall-clock), so it pauses correctly when the tree is paused.
- **Typed dicts (`Dictionary[K, V]`)** for `part_registry`, `voxel_data`, `_voxel_to_pending`. Plain `Dictionary` poisons inferred types from iteration (`for x in dict` makes `x` Variant).
- **Helper lambdas capture local refs, not `self`.** When a `RefCounted` class holds an `Array[Callable]` whose Callables reference instance fields, the implicit `self` capture forms a cycle. Pass dependencies as parameters and let lambdas close over the locals. See `ToolCatalog._build_catalog` for the pattern.
- **Cycle break in `_exit_tree`.** `StructuralIntegrity._exit_tree` calls `terrain_support.bind_part_support(null)` to break the `TerrainSupport ↔ PartSupport` reference cycle. Bus subscriptions auto-clean via WeakRef once the components' refcounts drop to zero.

### Persistence (`scripts/persistence/`, `scenes/world/world.gd`)

- **Terrain SDF**: continuous via `VoxelStreamSQLite` wired into `world.tscn` at `user://saves/world.db`. The stream persists edited blocks against the procedural generator automatically.
- **Snapshot**: F5 saves `user://saves/world.snapshot` (V4 schema, `var_to_str`-serialised); F9 reloads the scene. Save is gated on `StructuralIntegrity.is_quiescent()` — dirty queue empty, collapse detector idle, no awake `RigidBody3D` children — so the saved state is settled. The snapshot includes tracked voxels (with restored support), placed parts, player state, **shader tunables**, and **tool/activity indices**.
- **Restore path**: `world.gd:_ready` calls `WorldSnapshot.load_into` if the snapshot exists. Tracked voxels skip the propagation queue (saved values were captured while quiescent). Parts are restored by emitting `part_added` on the bus.
- **Version check is asymmetric**: newer-than-known schemas are rejected; older ones load with missing fields defaulted. So V2/V3 saves still load in V4 code, just without tunables / tool state.

### In-game console (Limbo Console)

`addons/limbo_console` is a git submodule pinned to v0.7.0. The `LimboConsole` autoload (set in `project.godot`) provides the runtime; `~` toggles. Commands are registered in `scenes/world/world.gd:_register_console_commands` — currently `set` (write a float shader uniform), `reset` (rewind to procedural defaults without touching save files), `quiescent`, `parts`, `voxels`, `tp`, `quit_game`.

**Reset semantics**: sets a `static var WorldSnapshot.reset_pending = true` flag (survives scene reload), then reloads the scene. World's `_enter_tree` sees the flag and detaches the SQLite stream so procedural terrain regenerates; `_ready` skips the snapshot load and clears the flag. F9 afterwards still restores the save normally.

**Known annoyance**: the Godot editor sometimes rewrites the `LimboConsole=` autoload entry in `project.godot` from `*res://addons/limbo_console/limbo_console.gd` to `*uid://...`, but the headless runtime can't resolve that UID (the addon was added via submodule and its UID isn't in `.godot/uid_cache.bin`). If runtime starts failing with `Nonexistent function 'register_command' in base 'Nil'`, fix is to swap the line back to the path form.

## Project State

See `docs/STATUS.md` for the current resumption brief and `docs/roadmap.md` for the version strategy. The status doc is the authoritative "where are we and what's next."
