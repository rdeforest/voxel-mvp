# Code Map

> **Where the code lives.** This is the structural reference for the shipped
> codebase — for Robert and for agents alike.
>
> Related docs, so you know when you're in the wrong one:
>
> - `docs/MANIFESTO.md` — *why the project exists.* Wins over everything.
> - `docs/roadmap/design/architecture.md` — *why the mechanisms work the way
>   they do* (lazy-expansion bounds, pause-correct delta accumulation, etc.).
> - `docs/roadmap.md` → Architectural Commitments — *which decisions are
>   immovable.*
> - `docs/STATUS.md` — *where we are and what's next.*
> - **This doc** — *where the code is and what the conventions are.*

---

## The substrate

Godot 4.6 built with **double-precision** (`precision=double` — cannot be
removed; it's compiled into the engine binary for planet-scale coordinates).

**The terrain data is the C++ `EditStore`** — a sparse octree of edits over a
C++ procedural generator (see Persistence).

**All meshing is our own Dual Contouring** (`engine/voxel_dc/`), not
Transvoxel. **godot_voxel is still built** (`tools/build`; the `voxel_dc`
module shares its ABI) but is **out of the running game** (Phase B): no
`VoxelLodTerrain` node, no godot_voxel storage, streaming, LOD, or collision
at runtime.

---

## Terrain rendering and collision

Everything sources SDF and material from the `EditStore`; nothing reads
godot_voxel. The subsystems are created in `world.gd:_ready`, not in
`world.tscn`.

**Render — `DcWorldPreview`** (`scripts/dc/dc_world_preview.gd`), the
`dcworld` render (doc 17). A single **world-fixed incremental octree**
(`DCOctreeMesher.mesh_world` / `grow_world`): screen-error LOD whose one knob
`eps_px` is driven by a frame-time + mesh-lag budget controller. A move
re-meshes only the changed band (incremental refine/coarsen). Default-on at
world startup. Wears the production terrain shader and material palette.

**Collision — `DCCollisionManager`** (`scripts/dc/dc_collision_manager.gd`).
Body-driven JIT collision, DC-meshed from the `EditStore` around the player.
Separate from the render.

Shared QEF solver in `engine/voxel_dc/dc_qef.h`.

Test coverage: `DCOctreeMesher` (`mesh_world`/`grow_world`) by
`test/test_dc_world_octree.gd`; the `mesh_clipmap` entry point (the
uniform/two-level meshing core, still used as a meshing harness) by
`test/test_dc_octree_mesher.gd` and `test/test_dc_real_terrain.gd`.

Known render bugs live in `docs/bugs/` (inside-coverage cracks, reversed ridge
triangles).

**Retired.** The camera-centered clipmap render (`DCTerrainManager`, the
`dcmanager` toggle), the `DcSubstratePreview`/`dcgen` substrate preview, the
GDScript SVO prototypes (`voxel_octree.gd`, `octree_mesher.gd`) and
`dc_edit_splicer.gd` were all removed once `DcWorldPreview` became the sole
render path.

---

## Scene graph

`world.tscn` holds only `StructuralIntegrity` and `Player`; the terrain
subsystems (`EditStoreManager`, `DcWorldPreview`, `DCCollisionManager`, …) are
instantiated in `world.gd:_ready`.

```
world.tscn
├── StructuralIntegrity  ← Node; facade composing the structural subsystem
└── Player (CharacterBody3D)
    ├── Head / Camera3D
    ├── RayCast3D
    └── EditPreview (MeshInstance3D)
   (terrain render/collision/data nodes added at runtime by world.gd)
```

`player.gd` acquires `StructuralIntegrity` via `get_parent().get_node()` in
`_ready`; it edits the terrain through the `EditStore` (sphere-traced aim via
`TerrainRaymarch`), not a terrain node.

---

## Action pattern (`scripts/actions/`)

Every world-modifying operation is an `Action` (`RefCounted`):

```gdscript
action.validate() -> bool   # refuses if constraints can't be satisfied
action.execute()  -> void   # performs the operation
```

`EditMode` (`scripts/edit_mode.gd`) is a data object holding callables for one
*activity* (Dig, Build, etc.). Activities are grouped under `Tool`s
(`scripts/tool.gd`) — four today: **None**, **Landscape**, **Construction**
(Build + Remove, where Remove digs the part's voxels), **CSG**.

The `ToolCatalog` (`scenes/player/tool_catalog.gd`) builds the tool array at
player startup, wiring each activity's `make_action` callable to an
`ActionFactories` (`scenes/player/action_factories.gd`) method.

**Input:** Tab cycles tools; 1–9 picks an activity within the current tool;
each tool remembers its last activity. On click, `player.gd:_try_edit_terrain`
calls `current_activity().make_action.call(hit_pos, hit_normal)`, then
`validate()` → `execute()`. Targeting logic (raycasting, sphere centers, build
placement) lives inside `ActionFactories`, not inside the Action.

**Adding an Action:** extend `Action`, implement `validate()` / `execute()` /
`preview()` / `to_step()` and a static `from_step()`, give it an op name in
`StepRegistry.ops()`, add a `make_*` factory to `ActionFactories`, and a new
`EditMode` entry under the appropriate tool in `ToolCatalog._build_catalog()`.
`test_step_registry.gd` round-trips every op; add yours there.

### Steps (`scripts/scenario/`)

An action as data, for recordings and hand-written scenarios (doc 22, Format 2).
*(Section drafted by Claude, 2026-09-27.)*

- `to_step()` returns the resolved constructor arguments; `StepRegistry.step_of()`
  adds the op name, and `StepRegistry.action_of(StepFields.new(step), ctx)`
  rebuilds the action in a context (a replay's store, player stand-in, source).
  The player's position is not in a step; the step stream carries it.
- `StepFields` owns the JSON shapes (vectors, cells, transforms, enum names,
  materials) and reads strictly: a missing, mistyped or extra field refuses.
- `StepDocument` is the file: a `format` / `version` / `units` header and one
  step per line.
- `StepJson` + `ExactDecimal` + `BigNat`: JSON whose doubles read back bit for
  bit. The engine's JSON reader is off by an ulp for about a quarter of doubles
  and drops `-0.0`'s sign, so numbers are read from their own text with correct
  rounding.
- `StepRegistry` also encodes the steps that aren't actions (`WORLD_OPS`):
  `player_at`, `advance`, `settle`, `mark`, `thaw` (the console's `mpmthaw`),
  `drain_support` (the console's `settle`).
- The replay runner and builder is `test/support/scenario.gd`: a headless world
  whose simulations tick only when it says (`advance`/`settle`, through the
  `tick()` seams on StructuralIntegrity, MpmStructure and DetachmentScout). A
  builder call (`s.dig(...)`) runs the step read back from its own JSON, the path
  `s.replay(text)` takes; replay stops at the first step whose `validate()`
  differs from its `expect_valid`. `s.capture()` is the world as bytes for
  comparing runs. The event bus is global, so one scenario is live at a time.
- `ScenarioRecorder` (`scripts/scenario/`) writes a directory the runner replays
  (`s.run_recording(dir)`): `steps.json`, the start's save pair unless it started
  fresh, and each mark's `mark-NNN.json` (+ `.png`). It takes the frame from its
  caller; the live caller is `RecordingCommands` (`scenes/world/`, console `rec`
  and `mark`), which counts its own unpaused physics frames and hears
  `Player.action_validated` plus the console's `thawing`/`draining_support`.
  A new store-writing console command must announce itself the same way, or a
  recording made across it won't replay.

### Instruments (`scripts/instruments/`, `scenes/world/instrument_commands.gd`)

Doc 22's instrument layer: exact, grid-aware console writes for testing, kept
apart from the player's verbs. *(Section drafted by Claude, 2026-09-27.)*

- `SetCornersAction` (`set_corners`), `SetMaterialAction` (`set_material`) and
  `StampAction` (`stamp`, a `CsgAction` without the safety refusal) are Actions
  with step ops, so recordings and the runner's builder hold them like any step.
  Each has `refusal()` (why `validate()` is false) and `written_field()` (the
  lattice `execute()` writes).
- `InstrumentCommands` is the console side (`setcorners`, `setmaterial`,
  `stamp`, `save`, `load`). Numbers go through `ExactDecimal`, not the console's
  parse. Every write takes `write()`: `validate()`, the `validated` signal
  (`RecordingCommands` records it as it does a click), then the write, then the
  rescue: `PlayerSafeAction.danger_of()` on the written field, read before the
  write, puts the player in fly mode (`Player.enter_fly`), with noclip when buried.

---

## Event bus (`scripts/events/`)

Two identifiers refer to the same thing for different purposes:

- **`VoxelEventBusSingleton`** — the autoload instance (registered in
  `project.godot`). Use this at call sites.
- **`VoxelEventBusType`** — the `class_name` of the script. Use this in type
  hints.

Godot 4 forbids a `class_name` matching any autoload name, hence the
`Type`/`Singleton` suffixes. The `Voxel` prefix is part of the name because
the bus has voxel-space spatial filtering, not just plain pub/sub.

Spatial pub/sub: subscribers register per-cell or channel-wide interest; the
bus dispatches each emitted event to overlapping subscribers.

```gdscript
VoxelEventBusSingleton.subscribe_cell(channel, cell, callback)
VoxelEventBusSingleton.subscribe(channel, callback)          # channel-wide
VoxelEventBusSingleton.emit(channel, event)
# matching unsubscribe_cell / unsubscribe (only for intentional cancel)
```

**Channel taxonomy** (`scripts/events/*_event.gd`):

- **Matter changed**: `terrain_sdf_changed` (`TerrainSdfChangedEvent`), emitted
  once by every write to the store: actions, the MPM thaw and freeze. It
  carries the rewritten box, the cells the write flipped (`CellFlips`, measured
  across it) and its `EditSource` (player, instrument, MPM, scout, replay).
  The per-cell `voxel_added`/`voxel_removed` events were folded into it
  (2026-09-27). A placement also emits `part_placed` for the `PartIndex`
  sidecar. (`part_added`/`part_removed` were deleted with `PartSupport` in
  parts-as-voxels S4.)
- **Derived**, emitted by integrity components: `region_collapsing`.
  (`voxel_support_changed` was removed in Phase 6 with its only consumer,
  `CollapseDetector`.)
- **Lifecycle**: `world_ready` (global, channel-wide, no cells).

**World-ready gate.** Gameplay and physics must not act on a half-streamed
world (player falling through ungrown ground; the structural sim classifying
support against an unloaded SDF). So `player.gd`, `StructuralIntegrity` and
`DetachmentScout` start `_active = false` and gate their
`_physics_process`/handlers until `WorldReadyEvent` arrives.

The terrain field is the C++ `EditStore` (generator plus edits), resident from
frame one — there's no godot_voxel streaming to wait on — so
`world.gd._process` emits `world_ready` on the **first frame** (`_world_ready`
one-shot guard). Nothing to poll, no timeout. The terrain render is **never**
gated. Subscribers must exist before the event fires; all current ones are
built at world startup.

Each event extends `VoxelEvent { grid_id, cells }`. `cells` is the dispatch
footprint the bus indexes per-cell subscribers against. `grid_id` is in every
payload from day one so multi-grid (5.5d, deferred) lands without payload
churn.

**Lifetime: WeakRef.** Each subscription stores `WeakRef(owner)` plus a method
name, not the bare `Callable`. When the subscriber is freed (Node
`queue_free`, or RefCounted refcount-to-zero) the WeakRef goes null and the bus
prunes lazily on the next emit. **No `dispose()` calls required.**

**Caveat:** subscribe with a bound method (`self.my_method`), not an anonymous
lambda. Lambdas have no Object to weakref and persist until manually
unsubscribed.

---

## Structural integrity

> **Authority note.** The live structural simulation is **PB-MPM**
> (`MpmStructure` plus the C++ `MpmSim`), wired at world startup.
> `TerrainSupport` is the **tracking spine** the sim rides on (`voxel_data`,
> `is_natural_terrain`); the loss-of-support trigger is `DetachmentScout` plus
> `GroundFlood` (flood-to-bedrock), which replaced the old scalar-support
> cascade.
>
> Parts are no longer a separate system: a placed part is imprinted into the
> EditStore (parts-as-voxels S2) and tracked as ordinary voxels, so MPM already
> simulates it. The old `PartSupport`/`PartData`/`collapse_part`/strain layer,
> the `CollapseDetector`/`IntegrityDebug` collapse layer, and the earlier PBD +
> `VoxelChunkBody` rigid-body path are all deleted. Part *identity* lives in the
> `PartIndex` sidecar.

**`StructuralIntegrity`** (`scripts/structural_integrity.gd`) is a `Node`
facade:

```
StructuralIntegrity (Node, facade)
├── terrain_support: TerrainSupport  ← voxel_data, is_natural_terrain, propagation
└── mpm:             MpmStructure    ← set by world.gd; the PB-MPM sim
```

The facade owns `_physics_process` orchestration (drain the support fixpoint at
`TerrainSupport.PROPAGATION_BUDGET`/frame once `WorldReadyEvent` flips
`_active`) and `is_quiescent`/`force_quiescent` for save gating — which
requires the dirty queue empty **and** `mpm.active_count() == 0`, since
in-flight MPM particles aren't serialised. It exposes the `get_support` query
and holds the `store` and `mpm` references `world.gd` injects. Bus-driven
structural reactions live in `TerrainSupport` and `DetachmentScout`, not the
facade.

**`TerrainSupport`** (`scripts/structural/terrain_support.gd`) owns
`voxel_data: Dictionary[Vector3i, VoxelRecord]`, `dirty_queue` and
`_lowest_registered_y`. Subscribes channel-wide in `_init` to
`terrain_sdf_changed`: it tracks the event's solid flips (with the material the
store holds there), drops its air flips, then scans the box. A worklist fixpoint drains
`dirty_queue` (FIFO, BFS-order) at `PROPAGATION_BUDGET` (200) cells per physics
frame via `process_dirty_queue()`. `is_natural_terrain(pos)` requires both
untracked-solid AND bedrock — the combination grants `FULL_SUPPORT` to
neighbours.

Classification cascade in `_support_from_neighbor`, in priority order: tracked
voxel → solid-above (skip) → solid-bedrock (FULL) → suspended-mass
(lazy-register, skip) → air (skip).

The scalar `support` it computes is no longer consumed by a collapse system. It
survives as the maintainer of the **tracked voxel set** and the **gate for
suspended-mass discovery**: `_support_from_neighbor` lazily registers a solid
neighbour as tracked when the current cell's support clears `FALL_THRESHOLD`.
This grows `voxel_data` as a dug-out overhang appears, but no longer *triggers*
the fall. Fully retiring the scalar means replacing that expansion with a
detachment-native criterion — a deliberate future task.

**Terrain collapse (PB-MPM).** The trigger is **`DetachmentScout`**
(`scripts/structural/detachment_scout.gd`): on a matter change, it gathers freshly-exposed solid cells as seeds and floods each connected
component **downward toward bedrock** via **`GroundFlood`** (`ground_flood.gd`
— non-blocking, a budget of cells per frame, capped at `MAX_DETACH` 700). A
component that drains without reaching bedrock under the cap is **DETACHED**
and handed to `MpmStructure.thaw_cells(...)`.

The scout tells edits apart by source: for its own detachment thaw (`SCOUT`)
it seeds only from the cells the thaw flipped outside the component it thawed
(the carve is solved to flip none, but the seeding follows measured flips, not the
promise), and it ignores `MPM` freezes, whose
flips aren't measured yet (`docs/bugs/mpm-freeze-flips-unmeasured.md`). It
pauses resolving while material is in flight, so
detachment proceeds in settled waves; edits made during flight are queued, not
dropped. That's what breaks the runaway cascade the old scalar trigger risked.
Terraforming (raise, lower, flatten) is a matter change like any other, so it
releases parts from `PartIndex` and can detach what it undercuts.

**MPM thaw/freeze lifecycle.** `MpmStructure`
(`scripts/structural/mpm_structure.gd`) wraps the C++ `MpmSim`. `thaw_cells`
carves detached cells out of the SDF and seeds MPM particles in their place
(rendered via a `MultiMesh`); the sim falls and deforms the continuum against
the rest of the terrain each `tick`. When particles settle (`_settled_frames`),
`_freeze()` rasterises the material back into the EditStore as terrain
(`mpm_couple`), queueing re-mesh boxes closest-to-camera-first
(`_pending_chunks`). `active_count() > 0` while any material is in flight —
this is what gates saves. No `RigidBody3D` is involved.

**Typed records** (all `RefCounted`, in `scripts/structural/`):

- `VoxelRecord` — `{support, material, dirty}` for tracked voxels.
- `PartRecord` — `{id, cells, material, dimensions, transform, ancestry}` for
  the `PartIndex` identity sidecar.

---

## Player composition (`scenes/player/`)

`player.gd` (a `CharacterBody3D`) composes five `RefCounted` helpers:

- **`PlayerMovement`** (`movement.gd`) — gravity, jump, WASD via `tick(delta)`.
  Shift suppresses horizontal movement (chord modifier).
- **`CameraRig`** (`camera_rig.gd`) — mouse motion, head/body rotation.
- **`BuildState`** (`build_state.gd`) — selected part, material, rotation,
  `placement_offset`. Emits `changed()` so the HUD label updates.
- **`ActionFactories`** (`action_factories.gd`) — one `make_*` per activity
  (probe, dig, fill, flatten, raise, lower, fill_voxel, empty_voxel,
  construction, removal). Holds `EDIT_RADIUS`.
- **`ToolCatalog`** (`tool_catalog.gd`) — builds the `Tool` array, each tool
  holding its activity `EditMode`s. Lambdas inside `_build_catalog` close over
  local parameters (`af`, `bs`) rather than `self`, avoiding catalog ↔ Callable
  cycles that would leak meshes at exit.

`player.gd` state: `tool_index: int` plus `_activity_indices: Array[int]` (one
per tool — last-activity memory). `current_tool()` and `current_activity()` are
the accessors. Input dispatch dicts (`_key_actions`, `_mouse_button_actions`)
and `_handle_placement_wheel` route Shift+W/A/E and wheel into
`build_state.adjust_offset` for free part placement.

---

## Parts (`scripts/schematics/`, `assets/parts/`)

**A placement is a voxel imprint, not a spawned Node3D.** `ConstructionAction`
stamps the part's box brush into the EditStore via the shared `VoxelImprint`
(parts-as-voxels S2), so the part becomes ordinary tracked voxels the DC mesher
draws and MPM simulates. There is no part scene, no part instance, and no
separate part-tracking system — identity goes to the `PartIndex` sidecar (S3),
which records each placement's `PartRecord` from a `part_placed` bus event.

`Schematic` (base, `Resource`) carries an optional hand-authored footprint.
`Part` extends it with `dimensions: Vector3`, `material_name: StringName`, and
`world_transform(basis, placement_pos)` — the single source for the ghost, the
footprint and the imprint placement. Bottom-anchored at local Y=0.

Current catalog (`assets/parts/<n>/<n>.tres`): `beam` 6×2×2 Wood, `slab` 4×2×4
Stone — parametric rectangular Parts differing only in `dimensions`. **The
2/4/6 m sizes are temporary testing dimensions:** at the 1 m grid a feature
needs ≥2 sample spacings to resolve (doc 03 Nyquist #1), so sub-metre parts wait
on the adaptive-density substrate. Adding a Part is a one-line `.tres`.

**Multi-axis rotation.** `ConstructionAction.rotation: Vector3` — continuous
degrees per axis; `BuildState` accumulates them in `ROTATION_STEP` (15°)
increments via `rotate_x/y/z`, so you can build ramps and angled trusses, not
just quarter-turns. Rotation is around the body's local origin (unrotated
bottom-center); afterward the instance is shifted so the rotated bottom lands at
`placement_pos.y` and the rotated horizontal centroid sits over
`placement_pos.x/.z`. Use `Transform3D(basis, Vector3.ZERO) * aabb` for AABB
rotation — Godot doesn't define `Basis * AABB`.

**Placement is free** along all three axes:
`ConstructionAction.placement_pos = hit_pos + BuildState.placement_offset`. The
offset accumulates from Shift+W/A/E and wheel ticks (camera-relative axes,
`WHEEL_STEP` = 0.05 m), and resets on each successful placement and on tool
cycle.

**Controls in Construction → Build:** `[` / `]` cycle parts; `R`/`T`/`Y` rotate
around Y/X/Z in 15° steps (HUD shows the angle); `M` cycles material;
Shift+W/A/E plus wheel adjusts offset. Shift+key always suppresses the
underlying WASD key — Shift+W is a distinct input from W, not "walk plus
something."

**Debug overlays:**

- `G` — voxel grid overlay (wireframes the targeted cell and its Chebyshev
  neighborhood; useful for understanding voxel boundaries during
  flatten/dig/fill).
- `F` — full-scene wireframe.
- `I` — incremental-edit re-meshing.

Structural and MPM debugging is via the console, not key toggles: `floodviz`
(visualise the detachment flood-to-bedrock), `mpmthaw` / `mpmdemo` (thaw real
terrain / spawn a demo block into MPM). The old `V`/`H` PBD stress-line and
`IntegrityDebug` support-cube overlays went with the PBD/collapse layers.

**Action preview rendering.** Every `Action` implements `preview() ->
ActionPreview`, returning the cells it would change classified by intent (`air`,
`solid`, `part`) plus a `refused` flag. The world-space `VoxelPreviewRenderer`
(`scenes/player/voxel_preview_renderer.gd`) builds an Action each frame from the
current raycast hit, calls `preview()`, and draws the cells via two
ImmediateMesh passes (visible / obscured). Outlines inset 0.05 to avoid
z-fighting with the DC surface. Refusal lerps intent colors toward grey. The
legacy idealised sphere/plane previews are gone for Dig/Fill/Flatten; Build
keeps its part-mesh ghost.

---

## Materials

`Materials` (`scripts/materials/materials.gd`) is a `Resource` subclass with
`@export` fields (`decay`, `albedo`, `angle_of_repose`, `failure_mode`). Data
lives in `assets/materials/<n>.tres`; the class exposes static singleton
accessors (`Materials.STONE`, etc.) that lazy-load via
`load("res://assets/materials/...")`. `Materials.from_name(StringName)` resolves
a Part's `material_name` to the singleton, falling back to STONE for unknown
names.

---

## SDF conventions

- Negative SDF = inside solid; positive = air. Surface at the zero-crossing.
- Use `SDF_AIR = 5.0` (not 1.0) to clear voxels — DC isosurface interpolation
  pulls the surface back toward solid neighbours unless the value is large
  enough.
- Use `SDF_SOLID_THRESHOLD = 0.0` to test solidity in queries.
- **A cell is read at its centre.** `VoxelUtils.sample_point(cell)` is the one cell → point
  mapping; `TerrainProbe.sdf/is_solid/material` read there. `Vector3(cell)` is the cell's min
  corner — a store lattice point, which only writers of lattice values (`StoreWrite`, `SdfLattice`)
  and DC diagnostics use. An edit's preview and voxel events come from one `CellFlips`:
  predicted by `SdfLattice.flips()` from the field the edit writes (dig/fill
  `SdfLattice.sphere_stamp` + `write()`, `StoreWrite`, `VoxelImprint` — all through
  `EditStore.write_region`, so the prediction IS the write), measured across the write for
  events: `SdfLattice.write` returns them (`EditStore.write_region_flips` reads each rewritten
  cell's sample just before and just after, `edit_store_write_flips.cpp`, gated against the
  GDScript `snapshot`/`since` by `test_lattice_write_flips`), with the pre-write material of each
  emptied cell (the MPM thaw's particles). Event materials are read back from the store.
  Construction's ghost (`part`) is its imprint's flips too (its AABB footprint only when the
  part flips no cell centre, and for the `PartPlaced` sidecar).
- **Player safety reads the written field, not cell flips.** `PlayerSafeAction.endangered_by`
  asks the edit's `SdfLattice` whether it turns any point of the capsule solid or of the
  support box air (`solidifies_in` / `empties_in`) — so a part or brush thinner than a cell,
  which can write real geometry without flipping a cell centre, is still refused.
  Construction's attach test likewise measures against the rotated brush at the imprint's
  lattice points, not the footprint.
- **Lattices are built and queried in C++.** Previews run every frame, so every `SdfLattice`
  builder (`sphere_stamp`, `VoxelImprint.lattice`, `StoreWrite.lattice`, the raise / lower /
  flatten reshapes) is `EditStore.predict_*`, and `flips` / `solidifies_in` / `empties_in` are
  `EditStore.lattice_flips` / `lattice_turns_in` (`engine/voxel_dc/edit_store_predict*.cpp`);
  Construction's attach test is `EditStore.imprint_near_solid`. Preview and write build the
  lattice through the same call. `test_edit_store_predict` (lattices, flips, safety) and
  `test_construction_attach_predict` (attach answers, bisected to the refusal boundary) gate them
  bit for bit against the GDScript originals, kept as the oracle in
  `test/support/lattice_oracle.gd`, on the store in `test/support/predict_store.gd`; a change to
  one needs the same change in the other.
- **A lattice's "before" is the rewritten leaf's own value.** Builders read each point with
  `EditStore.sample_toward`, so a point on the region's max faces is read from the leaf the write
  replaces, not the untouched neighbour `sample` would pick. `SdfLattice.writes` (CSG refuses on
  it) is exact: a point whose float32 changes, else `EditStore.lattice_writes`, a dry run of
  `write_region` over every corner of every leaf it would rewrite (`edit_store_dry_run.cpp`; it reads
  the array and the generator once per lattice point, not once per leaf corner). Material is not part of it.
- **A write moves nothing outside the leaves it rewrites.** Subdividing an edited leaf coarser
  than the write's cell doesn't re-store its children's corners: they read the subdivided leaf's own
  field (`EditStore::FieldState`, inherited leaves of a field source), so every sample outside the
  rewritten leaves is bit-identical before and after a write or stamp
  (`test_edit_store_subdivide_exact`). Inside, the field is the lattice's trilerp, even where it
  matches the old corners, so a write's `changed` can be true where `writes` is false
  (`docs/bugs/closed/edit-store-noop-write-reports-changed.md`).
- **Lattice writes are typed.** `StoreWrite` takes `Array[LatticeEdit]` (lattice point, new
  SDF, leaf material or -1 to keep) — FillVoxel, EmptyVoxel and the MPM carve all hand it that;
  `StoreWrite.lattice(store, work).flips(store)` is what the work does to cells. Bell and Flatten
  generate their work in C++ (`predict_bell` / `predict_flatten`) and write the lattice with
  `StoreWrite.reshape`, keeping each leaf's material.
- **Single-cell edits flip one cell or refuse.** `StoreWrite.one_cell` solves a small LP
  (`scripts/simplex.gd`) for the cell's 8 corner values so its centre crosses zero and none of its
  26 neighbours' centres do.
- All SDF and structural constants live in `VoxelConstants`
  (`scripts/voxel_constants.gd`).

---

## Key conventions

**Refuse-don't-deform.** Actions refuse via `validate()` when constraints can't
be met. Construction, CSG, Fill, FillVoxel, EmptyVoxel, Flatten and the bell
sculpts (Raise, Lower) ask `PlayerSafeAction.endangered_by` of the field they
write: each refuses to turn any point of the player's capsule solid or of the
support box under their feet air. Dig deliberately does not: players expect to
dig under themselves, and directives will replace it
(`docs/bugs/closed/dig-action-no-validate-no-safety.md`).
`ConstructionAction.validate` requires a part cell to overlap existing solid OR
rest directly on solid below — a part floating in air is refused, and one that
would bury the player is refused. Where an edit can't refuse but might overlap a
`RigidBody3D`, the action **freezes** the body before mutating the SDF
(`FillAction`/`CsgAction` → `PhysicsUtils.freeze_bodies_in`), so the next
physics tick doesn't squirt it sideways.

**Input dispatch via dictionary lookup.** `_key_actions` and
`_mouse_button_actions` map keycodes and buttons to callables. No if-chains.

**Mutations go through the bus.** Actions emit primitive events; they don't call
`StructuralIntegrity` directly for state changes. The remaining synchronous
facade query is `get_support`.

**Subscribe with bound methods, not lambdas.** `self.my_handler` lets the bus
weakref the owner and auto-clean.

**Typed dicts (`Dictionary[K, V]`)** for `voxel_data`, `PartIndex._records`.
Plain `Dictionary` poisons inferred types from iteration — `for x in dict` makes
`x` a Variant.

**Helper lambdas capture local refs, not `self`.** When a `RefCounted` holds an
`Array[Callable]` whose Callables reference instance fields, the implicit `self`
capture forms a cycle. Pass dependencies as parameters and let lambdas close
over the locals. See `ToolCatalog._build_catalog`.

---

## Persistence (`scripts/persistence/`, `scenes/world/world.gd`)

**Terrain SDF.** The **EditStore blob** (`EditStoreManager`, a sparse octree of
edits over the procedural generator) is saved to `user://saves/` by
`world.save_edit_store()` on F5 and restored in `world.gd:_ready`. Phase B
replaced godot_voxel's `VoxelStreamSQLite` with this. Parts persist here too —
they're imprinted voxels.

**Snapshot.** F5 saves `user://saves/world.snapshot` (V6 schema,
`var_to_str`-serialised); F9 reloads the scene. Save is gated on
`StructuralIntegrity.is_quiescent()` — dirty queue empty **and** MPM settled —
so the saved state is settled. The snapshot holds tracked voxels (with restored
support), player state, shader tunables, and tool/activity indices. It no longer
encodes parts separately.

**Restore path.** `world.gd:_ready` loads the snapshot if present, then the
EditStore blob. Tracked voxels skip the propagation queue — saved values were
captured while quiescent.

**Slots.** `SaveSlot` names where a pair lives: the default slot (F5/F9) is
`user://saves/` itself; console `save <name>` / `load <name>` use
`user://saves/<name>/`. A load marks the slot (`SaveSlot.request_load`) and
reloads the scene; `world._restore_save` takes it. F5 always saves the default.

**Version check is asymmetric:** newer-than-known schemas are rejected; older
ones load with missing fields defaulted. Pre-V6 saves still load, just without
newer sections (any Node3D parts they encoded are ignored — the world was reset
for the format change anyway).

---

## In-game console (Limbo Console)

`addons/limbo_console` is **vendored** (copied in, not a submodule) at upstream
v0.7.0 (`6e4c44d`). The `LimboConsole` autoload (set in `project.godot`)
provides the runtime; `~` toggles.

Commands live in `scenes/world/console_commands.gd` (a `ConsoleCommands` object
the World builds at `_ready`): `set`/`get` (shader uniforms), `reset` (rewind to
procedural defaults without touching save files), `quiescent`/`settle`, `parts`,
`voxels`, `tp`, `editstore`, plus DC/MPM debug toggles.
`register_all()`/`unregister_all()` wire them, guarded by `has_command` so scene
reloads don't re-register; `world._exit_tree` unregisters so a freed World
leaves no dangling callable.

**Addon policy: vendor, don't submodule.** GUT is vendored too. As a submodule,
LimboConsole caused persistent working-tree noise (Godot regenerates the addon's
`*.import` files, which a submodule flags as dirty) and a fragile autoload — the
script's UID intermittently failed to land in `.godot/uid_cache.bin`
(gitignored, machine-local), so the editor would serialize the autoload as
`*uid://…` but the runtime couldn't resolve it (`Nonexistent function
'register_command' in base 'Nil'`). The UID value itself (`dyxornv8vwibg`) is
fine; the failures were a stale cache from the half-converted submodule state.

**Reset semantics.** Sets `static var WorldSnapshot.reset_pending = true`
(survives scene reload), then reloads. World's `_ready` sees the flag and skips
loading the EditStore blob and snapshot, so the world regenerates from the
procedural generator; save files are untouched on disk. F9 afterwards still
restores normally.

The autoload is committed in path form
(`*res://addons/limbo_console/limbo_console.gd`) — safest for a fresh clone that
runs the game before opening the editor. The editor may rewrite it to
`*uid://dyxornv8vwibg`; with the addon vendored that resolves at runtime too. If
a runtime ever fails again with `Nonexistent function 'register_command' in base
'Nil'`, delete `.godot/uid_cache.bin` and run `bin/godot --headless --editor
--quit`, or swap the autoload line back to path form.

---

## Toast notifications

`Toast` autoload (`scripts/ui/toast.gd`) is a fading top-right log for
player-facing success and failure. Call from anywhere: `Toast.success(text)`,
`Toast.failure(text)`, `Toast.show_message(text, color)`. Used by save (F5) and
load (F9). Never captures input; animates while paused.

Note: `print()` goes to stdout — the VS Code **Debug Console** under a
`--remote-debug` launch, *not* the integrated terminal. Use Toast for anything
the player needs to see.
