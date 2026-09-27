# Record & replay → GUT regression tests: research

*Drafted by Claude (research agent), 2026-09-26. Read-only research; no repo files changed.*
Legend: **[V]** = verified by reading code / docs; **[I]** = inference, not verified by running anything.

---

## 1. Local findings

### 1.1 Where actions are built and executed

- **The only gameplay execute site** is `scenes/player/player.gd:274-291` (`_try_edit_terrain`):
  `activity.make_action.call(aim.position, aim.normal)` → `validate()` → `execute()`. [V]
  (grep for `.execute()` outside `scripts/dev/` and tests finds nothing else.)
- **Construction also happens every frame for the ghost**: `scenes/player/voxel_preview_renderer.gd:75`
  calls the same `make_action` and only `preview()`s it. [V] So a recorder must hook
  **execution**, not the factories or `Action._init` — hooking construction would log ~60 actions/s.
- Factories: `scenes/player/action_factories.gd:46-111` (one per EditMode), wired to activities
  in `scenes/player/tool_catalog.gd:160-224`. ActionContext is built once and cached
  (`action_factories.gd:38-41`). [V]
- Aim is resolved in `player.gd:298-317` (`current_target` → `TerrainRaymarch.surface` on the store,
  camera origin/forward; air-placement fallback along the camera ray). [V]

**Recommended single hook:** replace lines 285-291 of `player.gd` with a call to a small
`ActionJournal.run(action)` (or emit a signal just before `execute()`), passing the already-built
action. Record validate result too — "I clicked and nothing happened" (a refusal) is a bug class
worth replaying (cf. `docs/bugs/player-safety-misses-sub-cell-burial.md`).

### 1.2 What each action captures (is it pure in ctor args + store?)

Action lifecycle is documented as **single-use, build fresh, no other write between
validate/preview/execute** (e.g. `dig_action.gd:60-62`, `flatten_action.gd:60-62`). [V]
Replay must therefore *construct* actions at replay time from recorded args — never persist a
constructed action.

| Action | Ctor intent args | Reads at validate/execute beyond args+store |
|---|---|---|
| DigAction | position, radius, (shape) | none (no player) |
| FillAction | position, radius, material | `player.global_position` (safety); `player.get_world_3d()` physics query to freeze RigidBodies (`fill_action.gd:71-77`) |
| FlattenAction | plane_point, normal, radius | player position |
| Raise/LowerAction (BellSculpt) | position, radius (sign fixed by class) | player position |
| FillVoxelAction | cell, material | player position |
| EmptyVoxelAction | cell | player position |
| CsgAction | **shape (live CsgShape object)**, xform, op, material | player position; physics freeze on ADD (`csg_action.gd:87-94`) |
| ConstructionAction | **part (Part Resource)**, placement_pos, rotation, material | player position; `store.imprint_near_solid` (store only) |
| ProbeAction | hit_pos, hit_normal, offset | `integrity.terrain_support` (read-only, logs to console) |

Key facts:
- **Every PlayerSafeAction reads `player.global_position` at validate time**
  (`scripts/actions/player_safe_action.gd:31-35`). So each recorded step needs the player
  position at click time. Everything else is args + store. [V]
- The ActionContext holds the **live player node**, not a position (`action_context.gd`). Replay
  needs a `CharacterBody3D` stub *in the tree* (existing tests do exactly this:
  `test/test_player_safe_edits.gd:25-29`). [V]
- **CsgAction holds a reference to CsgState's mutable shape object** (`csg_state.gd:24-29`,
  `action_factories.gd:91-97`). A recorder must snapshot it as `(sdf_kind, sdf_dims)` at record
  time; there is no existing "CsgShape from kind+dims" constructor (would need one). [V for the
  reference; I for "no constructor" — I didn't find one in `scripts/csg/shape/`.]
- **ConstructionAction holds a Part Resource**; record `resource_path` *and* `dimensions`, so a
  later edit to the .tres is detected rather than silently changing the replay. [V/I]
- Factory-level nondeterminism that action-level recording sidesteps: `get_flatten_normal()` reads
  `Input.is_key_pressed(SHIFT/CTRL)` and the camera (`action_factories.gd:124-131`); placement
  chord reads keys + camera basis (`player.gd:253-258`); placement_offset / BuildState / CsgState
  feed args. Recording *resolved ctor args* makes all of that irrelevant. [V]
- Not every store mutation goes through an Action: console `mpmthaw`
  (`console_commands.gd:330-338`, uses the *physics* raycast, not the raymarch), `mpmdemo`,
  DetachmentScout → `MpmStructure.thaw_cells`, MPM freeze `rasterize_to_store`
  (`mpm_structure.gd:232`), `tp`. The first two are player-initiated and should be recorded as
  steps too; the last group are consequences and must be *re-simulated*, not recorded. [V]

### 1.3 Nondeterminism inventory

- **Randomness:** none in gameplay code. grep for `randi|randf|RandomNumberGenerator|randomize`
  outside `scripts/dev/` → nothing; C++ `mpm_sim.cpp`/`edit_store*.cpp` have no rand/threads.
  Terrain seed is a constant (`edit_store_manager.gd:20`, 1337) and is serialized in the blob
  (`edit_store_serialize.cpp:45,77`). [V]
- **Wall-clock:** `Time.get_ticks_usec` only feeds Perf reports and the DC controller
  (`dc_world_preview.gd` `refine_us`, `frame_budget`, `_job_work_ms`) — i.e. **render LOD is
  wall-clock- and hardware-dependent**, gameplay state isn't. [V]
- **Threads:** the DC mesher runs on `WorkerThreadPool` against `_edit_store.duplicate()`
  (`dc_world_preview.gd:319,333,354`; `edit_store.h:96`). Store writes stay on the main thread.
  So threads affect *what you see and when*, not the store. [V]
- **Frame-count-dependent simulation (the real replay hazard):** [V]
  - `TerrainSupport.process_dirty_queue` drains `PROPAGATION_BUDGET` per physics frame
    (`terrain_support.gd:111`).
  - `DetachmentScout` floods `BUDGET=400` cells/physics frame, and **ignores edits made while MPM
    is active** (`detachment_scout.gd:39-46, 63-75`). Whether a player edit triggers detachment
    depends on whether MPM was mid-fall at that frame.
  - `MpmStructure.tick(delta)`: `SETTLE_FRAMES=30`, `CHUNKS_PER_FRAME=2`
    (`mpm_structure.gd:17,200-215`). Physics delta is fixed (60 Hz default; project.godot sets no
    override) so MPM is plausibly bit-reproducible given the same tick count and inputs [I].
  - Freeze re-mesh chunks are **sorted by camera distance** (`mpm_structure.gd:253+`), which
    orders `TerrainSdfChangedEvent`s, which order DetachmentScout's `_pending` dict insertion,
    which orders floods. Camera-dependent event order → structural outcome. [V chain; I that it
    matters in practice]
    *Fixed 2026-09-27 (Claude, overnight G4.0): chunks are announced bottom layer first, by
    position; the camera plays no part. (G2 had already made the scout ignore MPM's events by
    source, so by then the order reached TerrainSupport's dirty queue, not the scout's floods.)*
- **Physics engine:** Jolt (`project.godot:87`). No RigidBodies are spawned any more (debris
  removed), so Jolt only moves the player. Player movement is *not* replayed at the action level
  (positions are recorded instead), so Jolt determinism isn't needed. Godot-Jolt explicitly
  does not guarantee determinism (see §2). [V/I]
- **Event bus** is synchronous, snapshot-then-dispatch, re-entrant (`voxel_event_bus.gd:99-105`).
  Subscriber order = subscription order. Deterministic given the same wiring order. [V]

### 1.4 What the save captures vs what a scenario needs

Saved [V] (`world_snapshot.gd:131-190`, `edit_store_manager.gd:36-56`):
- EditStore blob: sparse SDF + material tree + generator params + seed (not generator *code*).
- Snapshot v7: player position, body yaw, head pitch, tool/activity indices, build part path /
  material / rotation, tracked voxels (pos, material, support), terrain shader tunables, HUD
  window fractions.

Not saved:
- **PartIndex** (records, ancestry, `_next_id`) — created fresh in `world.gd:31`, never
  persisted. A scenario starting from a save loses part identity for pre-existing parts. [V] *Fixed
  2026-09-27 (Claude, overnight G4.0): the snapshot (v9) carries it, bit-exact.*
- CsgState (dims/op/rotation), placement_offset — irrelevant if steps record resolved args.
- MPM particles and TerrainSupport dirty queue — save is gated on `is_quiescent()`
  (`structural_integrity.gd:73-79`). [V]
- **DetachmentScout `_pending` / in-flight flood — not part of `is_quiescent()`**, so a save can
  drop a pending detachment. [V from reading; I that it happens in practice] *Fixed
  2026-09-27 (Claude, overnight G4.0): the gate waits for the scout, and for MPM freeze chunks not
  yet announced.*
- Camera FOV, dcworld knobs (radius, eps, refine, retain, max cells, threads), fly/noclip,
  examine state. Needed for **render** assertions, not store ones.
- Generator code version. A change to `terrain_field.h` silently changes unedited ground under a
  recorded scenario. [V that it isn't stored]
- Save pair can mismatch across saves undetected (`saved_world.gd:10`, the since-closed
  `save-pair-consistency` bug). [V] *Fixed 2026-09-27 (Claude, overnight G3): both halves carry one
  save id, the pair is written under temporary names and renamed in, and a lone or mismatched half
  is refused.*

Prior art in-repo: action-journal/replay was explicitly deferred as the network-sync primitive
(`docs/roadmap/implementation/done/extras-01-persistence.md:44-52`, design doc 05 "Replication
unit: OPERATIONS" with Lamport ordering), and FEAT045 "Replay harness … deterministic replay
against a saved snapshot" is on the 5.5 backlog
(`docs/roadmap/implementation/started/05-phase-5_5-architectural-maturation.md:253`). The
recording format should be designed as that journal, not a test-only side format. [V]

Test infrastructure already fits: GUT 9.6.0 vendored; tests build a real store via
`EditStoreManager.setup()`, a CharacterBody3D via `add_child_autofree`, and `ActionContext.new(
store, body, null)` (`test_player_safe_edits.gd`); MPM is tick-able headless
(`test_mpm_structure.gd:66-70`); DC meshing is callable synchronously with an explicit camera
(`DCOctreeMesher.mesh_world(store, origin, depth, base, cam, …)`, `test_dc_world_octree.gd:79`). [V]

---

## 2. External findings

**Godot record/replay addons.** Nothing mature for *gameplay-command* replay turned up. What exists
is frame/GIF capture ([GIF Replay Recorder](https://godotassetlibrary.com/asset/4S078v/gif-replay-recorder),
[GodotRecorder](https://github.com/henriquelalves/GodotRecorder)), a third-party MCP with
"input recording" ([KeeVeeG/godot-mcp](https://github.com/KeeVeeG/godot-mcp)), and forum threads
where the answer is "record inputs/events per tick and roll your own"
([forum 1](https://forum.godotengine.org/t/record-and-playback-replays/66508),
[forum 2](https://forum.godotengine.org/t/how-to-record-and-replay-game-events-demo-files/20626)).
Conclusion: build it; it's small, and the Action layer already is the command log.

**GUT 9.6 features** (verified present in `addons/gut/test.gd`):
- `use_parameters(params)` + `ParameterFactory.named_parameters` — one test function per
  scenario file. ([docs](https://gut.readthedocs.io/en/latest/Parameterized-Tests.html))
- `add_child_autofree`, `autofree` — player stub / sim nodes in tree.
- `wait_physics_frames(n)`, `wait_process_frames`, `wait_until(callable, max_time)`,
  `wait_for_signal` — only needed if we replay through the real scene; the store-level runner
  should tick explicitly instead (deterministic, fast).
- `double` / `partial_double` / `stub` — useful to stub the camera or LimboConsole, probably not
  needed.
- `assert_eq_deep` / `compare_deep` — for comparing cell-set digests with diff output.
- `pending(text)` — the right state for a freshly generated scenario before Claude adds asserts.
- `InputSender` (`addons/gut/input_sender.gd`) — synthesizes InputEvents; this is the
  *input-level* path we should avoid for regressions.
([GutTest class ref](https://gut.readthedocs.io/en/latest/class_ref/class_guttest.html))

**Practice / lessons.**
- Input-level ("keylogger") replay requires whole-game determinism and pins the build: Factorio
  replays only play on the exact game version that made them
  ([wiki: Desynchronization](https://wiki.factorio.com/Desynchronization),
  [FFF #188](https://factorio.com/blog/post/fff-188)). Riot spent ~a year making the LoL server
  deterministic, much of it unifying 8 clocks
  ([intro](https://technology.riotgames.com/news/determinism-league-legends-introduction),
  [unified clock](https://technology.riotgames.com/news/determinism-league-legends-unified-clock)).
  Their key tool: log state per tick and **diff to the first divergence** — everything after is
  noise ([fixing divergences](https://technology.riotgames.com/news/determinism-league-legends-fixing-divergences)).
- Record by **tick number, never time**; keep update order identical live vs replay
  ([GameDev.net thread](https://gamedev.net/forums/topic/673561-replay-recorded-games/)).
- Godot-Jolt does not guarantee determinism
  ([discussion #548](https://github.com/godot-jolt/godot-jolt/discussions/548)) — another
  reason not to replay movement/physics.
- Rare (Sea of Thieves) got reliability from many small, targeted gameplay tests over big
  end-to-end ones ([GDC 2019](https://gdcvault.com/play/1026366/Automated-Testing-of-Gameplay-Features),
  [slides](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
  Supports "trim to a minimal repro, then assert", not "keep the 10-minute recording".
- Trimming is **delta debugging** (ddmin): drop chunks of steps while the failure predicate still
  holds ([Zeller & Hildebrandt 2002](https://www.cs.purdue.edu/homes/xyzhang/fall07/Papers/delta-debugging.pdf),
  [Debugging Book](https://www.debuggingbook.org/html/DeltaDebugger.html)). Automatable only once
  the "looks wrong" has become a machine predicate — i.e. *after* Claude writes the assertion.
- Approval/golden-master tests pin current output and need scrubbers for unstable values
  ([ApprovalTests](https://approvaltests.com/),
  [scrubbers](https://github.com/approvals/ApprovalTests.Java/blob/master/approvaltests/docs/Scrubbers.md)).
  Here they pin *buggy* behavior by construction (the recording is of a bug), which conflicts
  with the project's own rule that consistency gates are not quality gates. Use snapshots only as
  a **replay-fidelity check**, never as the regression assertion.

**Input-level vs command-level, applied here:** input-level would need the raymarch aim,
camera, Jolt movement, frame timing, and the DC collision JIT to all match — none of which is
guaranteed. Command-level (resolved Action args + player position) depends only on the store,
the generator, and the action code — the things the test is actually about. Its brittleness is
different and acceptable: it breaks when an action's *semantics* change (which is often the point
of the test) or when the generator changes (detectable, see §3.5).

---

## 3. Recommendation

### 3.1 One language for recorded and hand-written scenarios

A `Scenario` builder whose methods *are* the step vocabulary, used directly by hand-written tests
and emitted verbatim by the recorder. Recorded file = a GDScript file of builder calls, so trimming
is deleting lines and the result is already a test.

```gdscript
# test/scenarios/2026-09-27_csg_sliver.gd  (generated; trimmed by hand/Claude)
static func play(s: Scenario) -> void:
    s.start_blob("res://test/scenarios/2026-09-27_csg_sliver.editstore")   # or s.start_fresh()
    s.player_at(Vector3(101.5, 34.0, 99.5))
    s.dig(Vector3(100.2, 31.1, 100.4), 3.0)
    s.csg(CsgSdf.Shape.BOX, [4.0, 1.0, 2.0], Transform3D(...), CsgState.Op.ADD, &"Stone")
    s.settle()                              # drain support + scout + MPM to quiescence
    s.mark("sliver on east face", {camera = Transform3D(...), fov = 75.0, aim_cell = Vector3i(...)})
```

Step vocabulary = one method per Action class with its resolved ctor args (`dig`, `fill`,
`flatten`, `raise`, `lower`, `fill_voxel`, `empty_voxel`, `csg`, `build`, `probe`), plus
`player_at`, `thaw` (mpmthaw with resolved centre), `advance(n_physics_frames)`, `settle()`,
`mark(note, view)`. Each action step also carries `expect_valid` (what validate() returned live);
replay **fails on the first divergence** instead of pressing on (Riot lesson).

Alternative if emitting GDScript float literals proves lossy: store steps as a `var_to_str` array
(the snapshot format already uses `var_to_str`, `world_snapshot.gd:23`) and have
`Scenario.load(path)` replay it. **Uncertain:** whether Godot 4.6 `var_to_str`/`str()` round-trip
doubles exactly — write a tiny round-trip test before choosing; a sub-ULP position change can move
a lattice decision. YAML is out (no built-in parser; would be a new dependency).

### 3.2 Minimal pieces

1. **Serializable actions.** Each Action gets `to_step() -> Dictionary` (op name + resolved args),
   and a registry maps op → constructor given an ActionContext. Needed changes: CsgShape
   snapshot/rebuild from `(sdf_kind, sdf_dims)`; Part by path + dims check. This is also the
   network journal's op record (doc 05) — build it once.
2. **Recorder hook** at `player.gd:285-291`: on click, append
   `{frame: Engine.get_physics_frames(), player: global_position, step: action.to_step(),
   valid: bool}`. Also record `mpmthaw`/`tp` from `console_commands.gd`. Start recording via a
   console `rec start` that requires `is_quiescent()` (same gate as F5) and copies
   `store.serialize()` + a PartIndex dump + snapshot voxels into the scenario dir; or `rec fresh`
   from a reset world (most reproducible: generator only).
3. **Mark command** (`mark [note]`, plus a key): writes the camera transform, FOV, dcworld knobs,
   player pos, the aimed cell + `ProbeAction.report()` lines, a screenshot PNG
   (`get_viewport().get_texture().get_image()`), and flushes the scenario file. The probe lines and
   aimed cell are what let Claude turn "looks wrong" into an assertion.
4. **Replay runner** (`test/support/scenario.gd`): headless, no World scene. Real
   `EditStoreManager` (+ `load_from` blob), `StructuralIntegrity`/`TerrainSupport` with
   `restore_voxel`, `PartIndex`, `MpmStructure`, `DetachmentScout`, a CharacterBody3D stub moved by
   `player_at`. Time is **explicit**: `advance(n)` / `settle()` call the sims' tick functions with
   `1.0/60.0`, never `wait_physics_frames`. Needs small seams: `DetachmentScout.tick()` and a
   `StructuralIntegrity` tick (MpmStructure already has `tick`, `mpm_structure.gd:200`), and the
   WorldReadyEvent gate emitted by the runner.
5. **Assertions** Claude adds after trimming, from the mark data:
   - store: `TerrainProbe.is_solid/material` at the marked cells, `store.sample` at points;
   - action outcome: `validate()` result, flip sets (`CellFlips`);
   - structure: `PartIndex.count/part_at`, MPM idle, detachment happened/not;
   - mesh: `DCOctreeMesher.mesh_world(store, …, cam_from_mark, …)` + the existing audits
     (crack audit, dangling-slot verify, watertight) — **caveat:** a fresh synchronous build does
     not exercise the live incremental grow/emit path or the wall-clock eps controller, so
     `dcdrop`-class bugs may not reproduce; those need a grow-sequence replay (camera path steps).
   New scenario tests start as `pending("replay only; add assertions")`, and must be shown to
   **fail on the buggy code** before the fix lands.

### 3.3 Trimming

Manual (delete lines) first. Once an assertion exists, a ddmin loop over steps (re-run the
scenario with subsets, keep the smallest that still fails) is ~40 lines of GDScript and
mechanical. `player_at` steps must stay paired with the actions after them.

### 3.4 Fidelity checks (so replays don't lie)

- `expect_valid` per step; fail at first mismatch.
- Optional per-step digest: hash of the flips measured by `SdfLattice.write`, or of the store's
  written region, recorded live and compared on replay → Riot-style "first divergence" report.
- Generator fingerprint: record `store.sample` at a handful of points near the scenario at record
  time; replay refuses with "generator changed" rather than failing an unrelated assertion.

### 3.5 Known limits / debts to name

- Timing-dependent structural bugs (edit landing while MPM is mid-fall) replay only with
  `advance(n)` using the recorded frame deltas; `settle()` between steps would hide them. Record
  the frames always; choose per scenario.
- Camera-sorted freeze chunks make structural event order camera-dependent; the runner needs a
  camera position (use the recorded one) or MPM should stop sorting by camera for anything but
  meshing priority. [I]
- Saves drop PartIndex and DetachmentScout pending work; scenarios started from an arbitrary F5
  inherit that. Prefer recorder-captured starts.
- Scenarios are coupled to action semantics and generator code by design; when a deliberate
  change breaks one, re-record or re-baseline explicitly — don't auto-update.
