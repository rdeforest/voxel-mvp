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

**`StructuralIntegrity`** (`scripts/structural_integrity.gd`): tracks only *modified* voxels in a `voxel_data` dictionary. Untracked voxels are assumed fully supported (they're natural terrain). A worklist fixpoint propagation drains `dirty_queue` at `PROPAGATION_BUDGET` (200) voxels per physics frame. When a voxel's support increases meaningfully, it emits `voxel_support_increased`.

**`CollapseDetector`** (`scripts/collapse_detector.gd`): runs after the dirty queue settles. Flood-fills connected components of unsupported voxels into *pending collapses* with a strain countdown (`STRAIN_DURATION_SEC = 3.0s`). During the window the player can add support to reset the timer. On expiry, the component is extracted from the SDF terrain and materialized as a falling `RigidBody3D` (greedy box merge for collision).

### Materials

`Materials` (`scripts/materials.gd`) is a class with static singleton instances (`Materials.STONE`, `Materials.WOOD`, etc.). Each carries `decay` (support loss per step of distance from ground) and `failure_mode`. Currently STONE is used for all player-placed voxels.

### SDF conventions

- Negative SDF = inside solid; positive = air. Surface at zero-crossing.
- Use `SDF_AIR = 5.0` (not 1.0) to clear voxels — Transvoxel interpolation pulls the surface back toward solid neighbors unless the value is large enough.
- Use `SDF_SOLID_THRESHOLD = 0.0` to test solidity in queries.
- All SDF and structural constants live in `VoxelConstants` (`scripts/voxel_constants.gd`).

### Key conventions

- **Refuse-don't-deform.** Actions refuse via `validate()` when constraints can't be met rather than silently adjusting.
- **Input dispatch via dictionary lookup.** `player.gd` maps keycodes and mouse buttons to callables; no if-chains.
- **`PLAYER_CLEARANCE = 1.0m`** in `FillAction` and `FlattenAction` prevents filling the player's occupied space. Tune if the player `CapsuleShape3D` dimensions change.
- Signals (not an event bus) connect `StructuralIntegrity` → `CollapseDetector` for `voxel_support_increased`.
- Strain timer accumulates against physics `delta` (not wall-clock), so it pauses correctly when the game tree is paused.

## Project State

See `docs/STATUS.md` for the current resumption brief and `docs/roadmap.md` for the version strategy. The status doc is the authoritative "where are we and what's next."
