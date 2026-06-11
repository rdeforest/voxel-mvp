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

### Editor ↔ external-edit workflow (avoid the clobber)

The Godot **editor GUI** and external edits (VS Code, Claude, the CLI) both write
project files, and the editor wins on save: it re-saves any `.tscn` it has open and
**silently reverts external `.tscn` edits**, regenerates `.import`/`.uid`/`.godot/`,
and pops "files changed on disk" dialogs. This has already invalidated a play
session (a `generate_collisions = false` edit was eaten → double collision →
phantom "targeting bug"). Protocol:

- **Keep the editor GUI closed during co-dev.** Run/test the game via VS Code's
  godot-tools debug (F5, `--remote-debug` → output in the Debug Console) or
  `bin/godot --path .` — neither needs the editor GUI open.
- **Open the editor GUI only for deliberate visual scene work**, as an isolated
  mode switch: commit/stash pending changes first; when done, close it and reload
  any externally-changed files. Don't leave it open in the background.
- **Prefer code over `.tscn`** for settings Claude/CLI set (e.g.
  `generate_collisions` is set in `world._enter_tree`, not the scene) — `.gd` files
  are edited in VS Code, outside the editor's save path, so they don't collide.
- Claude's class-cache regen (`bin/godot --headless --editor --quit`, needed after
  adding a `class_name`) writes `.godot/` — run it only with the editor GUI closed.

## Architecture

This is a Godot 4.6 game built with **double-precision** (`precision=double` — cannot be removed; it's compiled into the engine binary for planet-scale coordinates) and the **godot_voxel** module for voxel storage / streaming / LOD / collision. **Terrain meshing is our own Dual Contouring**, not Transvoxel (godot_voxel ships no DC).

### Terrain meshing / rendering (Dual Contouring)

Two DC meshers, both ours (`engine/voxel_dc/`):
- **`VoxelMesherDC`** — per-block DC, set as the terrain's `mesher` in `world.tscn`. godot_voxel builds terrain **collision** from these blocks. Has LOD-boundary seam cracks (the "F2" problem).
- **`DCOctreeMesher`** + **`DCTerrainManager`** (`scripts/dc/dc_terrain_manager.gd`) — the "path-b" render layer: meshes the camera vicinity as ONE octree clipmap (crack-free LOD) on a worker thread and **renders that**, hiding godot_voxel's per-block render via `render_layers_mask = 0`. Default-on at startup (`start_default()`); `dcmanager`/`dcsolo` console commands toggle/override. Re-meshes on movement and on `terrain_sdf_changed` edits.

So: **render = `DCOctreeMesher`, collision = `VoxelMesherDC`** (both DC, both ours, both C++ in `engine/voxel_dc/`). Shared QEF solver in `engine/voxel_dc/dc_qef.h`. `DCOctreeMesher` is covered by `test/test_dc_octree_mesher.gd` (watertight + crack-free LOD transition) and `test/test_dc_real_terrain.gd` (real terrain); `DCRegionReader` by `test/test_dc_region_reader.gd`. The GDScript prototype *render* meshers were retired once this C++ path became production. `scripts/dc/` now holds: `dc_terrain_manager.gd` + `dc_collision_manager.gd` (live render/collision managers), `dc_edit_splicer.gd` (incremental edit-patch array surgery), and `voxel_octree.gd` + `octree_mesher.gd` — **the Phase B substrate prototypes** (the GDScript oracle `SparseVoxelOctree` was ported from; actively maintained for the adaptive-octree-substrate work, NOT dead — see `docs/roadmap/design/10-adaptive-octree-substrate.md`). The single-mesher consolidation (collision from our octree mesh, drop per-block visual meshing) is a deferred cleanup.

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

`EditMode` (`scripts/edit_mode.gd`) is a data object holding callables for one *activity* (Dig, Build, etc.). Activities are grouped under `Tool`s (`scripts/tool.gd`) — four today: **None**, **Landscape**, **Construction** (Build + Remove, where Remove digs the part's voxels), **CSG**. The `ToolCatalog` (`scenes/player/tool_catalog.gd`) builds the tool array at player startup, wiring each activity's `make_action` callable to an `ActionFactories` (`scenes/player/action_factories.gd`) method.

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
- **Primitive** (emitted by actions): `terrain_sdf_changed`, `voxel_added`, `voxel_removed`. (`part_added`/`part_removed` were deleted with `PartSupport` in parts-as-voxels S4; a placement now emits `part_placed` for the `PartIndex` sidecar — see "Parts".)
- **Derived** (emitted by integrity components): `region_collapsing`. (`voxel_support_changed` was removed in Phase 6 with its only consumer, `CollapseDetector`.)
- **Lifecycle**: `world_ready` (global, channel-wide; no cells). See "World-ready gate" below.

**World-ready gate.** Gameplay + physics must not act on a half-streamed world (player falling through ungrown ground; PBD anchoring against an SDF that hasn't loaded). So `player.gd`, `StructuralIntegrity`, and `PbdStructure` start `_active = false` and gate their `_physics_process` until they receive `WorldReadyEvent`. `world.gd._process` polls the terrain (`get_voxel_tool().is_area_editable(box around the player)`) each frame and emits `world_ready` once the data has streamed in — with a `WORLD_READY_TIMEOUT` backstop so a bad probe can't freeze the game. The terrain node is **never** gated (pausing it would stall the very streaming we wait on). Subscribers must exist before the event fires (all current ones are built at world startup). PBD additionally keeps a per-structure anchor guard (`_unanchored`) for a structure that spans beyond the loaded area.

Each event extends `VoxelEvent { grid_id, cells }`. `cells` is the dispatch footprint — the bus indexes per-cell subscribers against it. `grid_id` is in every payload from day one so multi-grid (Phase 5.5d, deferred) lands without payload churn.

**Lifetime: WeakRef.** Each subscription stores `WeakRef(owner) + method name`, not the bare `Callable`. When the subscriber is freed (Node `queue_free`, or RefCounted refcount-to-zero), the WeakRef goes null and the bus prunes lazily on next emit. **No `dispose()` calls required.** Subscribers can be created and forgotten.

**Caveat:** subscribe with a bound method (`self.my_method`), not an anonymous lambda. Lambdas have no Object to weakref and would persist until manually unsubscribed.

### Structural integrity system

> **Authority note.** The live structural simulation is **PBD** (`PbdStructure` +
> the C++ `PbdSim`), enabled by default at world startup — see "PBD structural
> simulation" below. The classes here are the **tracking spine** PBD rides on
> (`TerrainSupport.voxel_data` / `is_natural_terrain`) plus the **falling-chunk
> lifecycle** PBD reuses. Parts are no longer a separate system: a placed part is
> imprinted into the EditStore (parts-as-voxels S2) and tracked as ordinary voxels,
> so PBD already simulates it. The old `PartSupport`/`PartData`/`collapse_part`/
> strain layer and the `CollapseDetector`/`IntegrityDebug` collapse layer are all
> deleted. Part *identity* lives in the `PartIndex` sidecar (see "Parts").

**`StructuralIntegrity`** (`scripts/structural_integrity.gd`) is a `Node` facade:

```
StructuralIntegrity (Node, facade)
├── terrain_support: TerrainSupport   ← voxel_data, is_natural_terrain, propagation (the tracked set PBD reads)
└── pbd:             PbdStructure      ← set by world.gd; the authoritative sim; folded into is_quiescent
```

The facade owns `_physics_process` orchestration (drain the support fixpoint; classify falling bodies), `wake_falling_bodies` (needs scene-tree access), and `is_quiescent` (save gating — also requires `pbd.is_settled()`). Mutations come through the bus; the facade exposes the `get_support` query. It subscribes `terrain_sdf_changed` in `_ready` so it can call `wake_falling_bodies` when the world changes.

**`TerrainSupport`** (`scripts/structural/terrain_support.gd`) owns `voxel_data: Dictionary[Vector3i, VoxelRecord]`, `dirty_queue`, and `_lowest_registered_y`. Subscribes channel-wide in `_init` to `voxel_added`, `voxel_removed`, and `terrain_sdf_changed`. A worklist fixpoint drains `dirty_queue` (FIFO, BFS-order) at `PROPAGATION_BUDGET` (200) cells per physics frame via `process_dirty_queue()`. `is_natural_terrain(pos)` requires both untracked-solid AND bedrock — the combination grants `FULL_SUPPORT` to neighbours.

Classification cascade in `_support_from_neighbor` (priority order): tracked voxel → solid-above (skip) → solid-bedrock (FULL) → suspended-mass (lazy-register, skip) → air (skip).

The scalar `support` it computes is no longer consumed by a collapse system — it survives only as the **gate for suspended-mass discovery**: `_support_from_neighbor` lazily registers a solid neighbour as a tracked cell when the current cell's support clears `FALL_THRESHOLD`, which is how a dug-out overhang becomes the cells PBD simulates. (Fully retiring the scalar would mean replacing that expansion with a PBD-native criterion — a deliberate future task.)

**Terrain collapse** is PBD's job (see below). It hands the detached cells to `VoxelChunkBody.from_voxels(cells, store)` (`scripts/structural/voxel_chunk_body.gd`) → a `RigidBody3D` whose **visual is a Dual-Contoured mesh of the chunk's own SDF** (sampled before the carve, masked to the component, painted per-cell from `MaterialPalette`) and whose **collision is a greedy-merged box-compound** (V-HACD off-thread is a later upgrade) — then carves the cells out of the SDF. The old flood-fill `CollapseDetector` was deleted in Phase 6.

**Falling body lifecycle.** `VoxelChunkBody` stashes `cell_offsets` (each origin cell's local-space offset from the body's centroid at collapse time) on the body via `set_meta`. `StructuralIntegrity._tick_falling_bodies()` runs every physics frame: for each body with `cell_offsets`, sample SDF at each cell's current world position (via `body.global_transform * offset`):
- **All cells in solid SDF (fully buried)** → emit `voxel_added` per cell at its current world-cell, free the body. The fallen mass becomes tracked SDF terrain.
- **Some cells in solid (partially buried)** → `body.freeze = true`. Body locks in place; physics stops simulating it.
- **No cells in solid (free)** → leave alone; physics handles it (sleeps when at rest). If the body was previously frozen and is now free (e.g., player dug terrain out from around it), unfreeze and wake.

`FillAction.execute` freezes any overlapping `RigidBody3D` **before** mutating SDF, so the next physics tick doesn't squirt the body sideways from the collision overlap. The classifier integrates them on subsequent ticks.

Typed records (all `RefCounted`, in `scripts/structural/`):
- `VoxelRecord` — `{support, material, dirty}` for tracked voxels.
- `PartRecord` — `{id, cells, material, dimensions, transform, ancestry}` for the `PartIndex` identity sidecar.

Detailed mechanism rationale (lazy-expansion bounds, pause-correct delta accumulation, etc.) lives in `docs/architecture.md`. The doc complements `roadmap.md → Architectural Commitments` (design-level decisions) and this file (where the code lives).

### Player composition (`scenes/player/`)

`player.gd` (a `CharacterBody3D` Node) composes five `RefCounted` helpers:

- `PlayerMovement` (`movement.gd`) — gravity, jump, WASD via `tick(delta)`. Shift suppresses horizontal movement (chord modifier).
- `CameraRig` (`camera_rig.gd`) — mouse motion, head/body rotation.
- `BuildState` (`build_state.gd`) — selected part, material, rotation, `placement_offset`. Emits `changed()` so the HUD label updates.
- `ActionFactories` (`action_factories.gd`) — one `make_*` per activity (probe, dig, fill, flatten, raise, lower, fill_voxel, empty_voxel, construction, removal). Holds `EDIT_RADIUS`.
- `ToolCatalog` (`tool_catalog.gd`) — builds the `Tool` array (None / Landscape / Construction), each tool holding its activity `EditMode`s. Lambdas inside `_build_catalog` close over local parameters (`af`, `bs`) rather than `self`, to avoid catalog ↔ Callable cycles that would leak meshes at exit.

`player.gd` state: `tool_index: int` plus `_activity_indices: Array[int]` (one per tool — last-activity memory). `current_tool()` and `current_activity()` are the accessors. Input dispatch dicts (`_key_actions`, `_mouse_button_actions`) and `_handle_placement_wheel` route Shift+W/A/E + wheel into `build_state.adjust_offset` for free part placement.

### Parts (`scripts/schematics/`, `assets/parts/`)

A **placement is a voxel imprint**, not a spawned Node3D: `ConstructionAction` stamps the part's box brush into the EditStore via the shared `VoxelImprint` (parts-as-voxels S2), so the part becomes ordinary tracked voxels the DC mesher draws and PBD simulates. There is no part scene/instance and no separate part-tracking system — identity goes to the `PartIndex` sidecar (S3), which records each placement's `PartRecord` from a `part_placed` bus event.

`Schematic` (base, `Resource`) carries an optional hand-authored footprint. `Part` extends it with `dimensions: Vector3`, `material_name: StringName`, and `world_transform(basis, placement_pos)` (the single source for the ghost, the footprint, and the imprint placement). Bottom-anchored at local Y=0.

Current catalog (`assets/parts/<name>/<name>.tres`): `beam` 6×2×2 Wood, `slab` 4×2×4 Stone — parametric rectangular Parts differing only in `dimensions`. The 2/4/6 m sizes are **temporary testing dimensions**: at the 1 m grid a feature needs ≥2 sample spacings to resolve (doc 03 Nyquist #1), so sub-metre parts wait on the adaptive-density substrate. Adding a Part is a one-line `.tres`.

Multi-axis rotation: `ConstructionAction.rotation: Vector3` — continuous **degrees** per axis (X, Y, Z); `BuildState` accumulates them in `ROTATION_STEP` (15°) increments via `rotate_x/y/z`, so you can build at angles (ramps, angled trusses), not just quarter-turns. Rotation is around the body's local origin (the unrotated bottom-center); after rotation, the instance is shifted so the rotated bottom lands at `placement_pos.y` and the rotated horizontal centroid sits over `placement_pos.x/.z`. Use `Transform3D(basis, Vector3.ZERO) * aabb` for AABB rotation (Godot doesn't define `Basis * AABB`).

**Placement is free** along all three axes — `ConstructionAction.placement_pos = hit_pos + BuildState.placement_offset`. The offset accumulates from Shift+W/A/E + wheel ticks (camera-relative axes, WHEEL_STEP = 0.05m). The offset resets on each successful placement and on tool cycle.

Player controls in **Construction → Build** activity: `[`/`]` cycle parts, `R/T/Y` rotate around Y/X/Z in 15° steps (HUD shows the current angle), `M` cycles material, Shift+W/A/E + wheel adjusts offset. Shift+key always suppresses the underlying WASD movement key — Shift+W is a distinct input from W, not "walk + something."

**Debug overlays:**
- `V` toggles the **PBD stress-line overlay** (`PbdStructure.toggle_viz` → the green→red→whitening member lines). The old `IntegrityDebug` support-cube overlay and its `H` obscured-pass toggle were removed in Phase 6.
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

- **Refuse-don't-deform.** Actions refuse via `validate()` when constraints can't be met. `FillAction` extends this to physics state via `intersect_shape` — fills that would overlap a `RigidBody3D` are refused. `ConstructionAction.validate` requires a part cell to overlap existing solid OR rest directly on solid below — a part floating in air is refused, and one that would bury the player is refused.
- **Input dispatch via dictionary lookup.** `_key_actions` and `_mouse_button_actions` map keycodes/buttons to callables; no if-chains.
- **`PLAYER_CLEARANCE = 1.0m`** in `FillAction` and `FlattenAction` prevents filling the player's occupied space.
- **Mutations go through the bus.** Actions emit primitive events (`terrain_sdf_changed`, `voxel_added`, etc.); they don't call `StructuralIntegrity` directly for state changes. The remaining synchronous facade query is `get_support`.
- **Subscribe with bound methods, not lambdas.** `self.my_handler` lets the bus weakref the owner and auto-clean. `func(e): handle(e)` has no Object to weakref and would leak until manually unsubscribed.
- **Wake-on-mutate.** `wake_falling_bodies()` is bus-triggered: `StructuralIntegrity` subscribes to `terrain_sdf_changed`. SDF terrain edits don't signal contact-change to the physics engine, so resting `RigidBody3D`s need an explicit nudge.
- **Typed dicts (`Dictionary[K, V]`)** for `voxel_data`, `PartIndex._records`. Plain `Dictionary` poisons inferred types from iteration (`for x in dict` makes `x` Variant).
- **Helper lambdas capture local refs, not `self`.** When a `RefCounted` class holds an `Array[Callable]` whose Callables reference instance fields, the implicit `self` capture forms a cycle. Pass dependencies as parameters and let lambdas close over the locals. See `ToolCatalog._build_catalog` for the pattern.

### Persistence (`scripts/persistence/`, `scenes/world/world.gd`)

- **Terrain SDF**: the **EditStore blob** (`EditStoreManager`, a sparse octree of edits over the procedural generator) is saved to `user://saves/` by `world.save_edit_store()` on F5 and restored in `world.gd:_ready`. Phase B replaced godot_voxel's `VoxelStreamSQLite` stream with this. Parts persist here too — they're imprinted voxels.
- **Snapshot**: F5 saves `user://saves/world.snapshot` (V6 schema, `var_to_str`-serialised); F9 reloads the scene. Save is gated on `StructuralIntegrity.is_quiescent()` — dirty queue empty, PBD settled, no awake `RigidBody3D` children — so the saved state is settled. The snapshot holds tracked voxels (with restored support), player state, **shader tunables**, and **tool/activity indices**; it no longer encodes parts separately (they live in the EditStore blob).
- **Restore path**: `world.gd:_ready` loads the snapshot (if present) and the EditStore blob. Tracked voxels skip the propagation queue (saved values were captured while quiescent).
- **Version check is asymmetric**: newer-than-known schemas are rejected; older ones load with missing fields defaulted. So pre-V6 saves still load, just without newer sections (and any Node3D parts they encoded are ignored — the world was reset for the format change anyway).

### In-game console (Limbo Console)

`addons/limbo_console` is **vendored** (copied into the repo, not a submodule) at upstream v0.7.0 (`6e4c44d`). The `LimboConsole` autoload (set in `project.godot`) provides the runtime; `~` toggles. Commands live in `scenes/world/console_commands.gd` (a `ConsoleCommands` object the World builds at `_ready`): `set`/`get` (shader uniforms), `reset` (rewind to procedural defaults without touching save files), `quiescent`/`settle`, `parts`, `voxels`, `tp`, `editstore`, plus DC/PBD debug toggles. `register_all()`/`unregister_all()` wire them, guarded by `has_command` so scene reloads (F9, `reset`) don't re-register; `world._exit_tree` unregisters so a freed World leaves no dangling callable.

**Addon policy: vendor, don't submodule.** GUT is vendored too. As a submodule, LimboConsole caused two problems: persistent working-tree noise (Godot regenerates the addon's `*.import` files, which a submodule flags as dirty), and a fragile autoload — the script's UID intermittently failed to land in `.godot/uid_cache.bin` (gitignored, machine-local), so the editor would serialize the autoload as `*uid://…` but the runtime couldn't resolve it (`Nonexistent function 'register_command' in base 'Nil'`). The UID value itself (`dyxornv8vwibg`) is fine; the failures were a stale cache from the half-converted submodule state. Vendoring (a plain project dir) plus a clean cache rebuild registers the UID normally, after which both the path and UID forms resolve. When updating LimboConsole, re-vendor from the pinned upstream commit and re-check the autoload boots clean.

**Reset semantics**: sets a `static var WorldSnapshot.reset_pending = true` flag (survives scene reload), then reloads the scene. World's `_ready` sees the flag and skips loading the EditStore blob + snapshot, so the world regenerates from the procedural generator; the save files are left untouched on disk. F9 afterwards still restores the save normally.

The autoload is committed in path form (`*res://addons/limbo_console/limbo_console.gd`) — safest for a fresh clone that runs the game before opening the editor. The editor may rewrite it to `*uid://dyxornv8vwibg`; with the addon vendored that resolves at runtime too, so either form is fine. If a runtime ever fails again with `Nonexistent function 'register_command' in base 'Nil'`, the autoload UID isn't in `.godot/uid_cache.bin` — delete that file and run `bin/godot --headless --editor --quit` (or just open the editor) to rebuild it, or swap the autoload line back to path form.

### Toast notifications

`Toast` autoload (`scripts/ui/toast.gd`) is a fading top-right log for player-facing success/failure. Call from anywhere: `Toast.success(text)` / `Toast.failure(text)` / `Toast.show_message(text, color)`. Used by save (F5) and load (F9). It never captures input and animates while paused. Note: `print()` goes to stdout (the VS Code **Debug Console** under a `--remote-debug` launch, *not* the integrated terminal) — use Toast for anything the player needs to see.

## Project State

**Read `docs/MANIFESTO.md` first** — it is the vision authority (if anything contradicts it, the manifesto wins). Core stance: **infinite programming resources, no half-measures** — design choices are made as if programming effort were unlimited; the only legitimate trade-offs are hardware limits (looks vs performance on real silicon), never "this is more work" or "good enough for now." This *inverts* the general "prefer the boring/minimal solution" instinct for architecture and scope (minimalism still applies to code *expression* — small diffs, no needless complexity — not to ambition). When tempted to propose "as-is," "opt-in," "defer the hard part," or "accept the slower path," that's the Enterprise habit, not the thesis — override it.

Then see `docs/STATUS.md` for the current resumption brief and `docs/roadmap.md` for the version strategy. The status doc is the authoritative "where are we and what's next."
