# Voxel Valheim MVP — Project Roadmap v2

**Engine:** Godot 4.6.x stable + Zylann's godot_voxel
**Assets:** Creative Commons / open-source
**AI Assist:** Claude Code for boilerplate, systems scaffolding, iteration
**Working Title:** TBD (not Norse mythology — see Post-MVP Vision)

---

## Design Principles

These aren't aesthetic preferences — they're the architectural thesis that justifies
choosing voxel over heightmap:

1. **Terrain IS geometry.** No distinction between "world" and "placed objects." A wall
   you build and the cliff behind it are the same data structure. A house made of dirt
   follows the same structural rules as a house made of wood.

2. **No loading screens.** Caves, dungeons, and underground spaces exist in the same
   continuous voxel volume as the surface. You walk in, you don't teleport.

3. **Destruction and construction are real.** Digging a hole removes voxels. Building a
   wall adds them. The engine doesn't care whether terrain was generated or player-placed.

4. **Material physics matter.** Dirt has an angle of repose. Stone can span gaps. Wood is
   strong but burns. Every material in the world follows the same structural integrity
   rules, whether it's terrain or construction.

5. **Moore's Law is a market dynamic.** Don't over-optimize for 2025 hardware. Build the
   right architecture and let hardware catch up.

---

## Version Strategy

| Version | Question it answers | Roughly maps to |
|---------|-------------------|-----------------|
| 0.0 | Is this as good of an idea as I think it is? | Phases 0, 2, 5 (fast path) |
| 0.0.1 | Can I save, load, and replay the world? | Persistence + history-as-journal (see below) |
| 0.1 | Can I make it fun/performant? | Phases 1, 3, 4 (filling in the gameplay) |
| 0.2 | Can I make it pretty? | Art pass, shader work, audio, polish |
| 0.9 | Can I make it into a real product? | Multiplayer, content depth, settings, QA |
| 1.0 | Will people pay to get it from Steam? | Open-source + Steam for cloud saves, multiplayer |
| 1.1 | Can I make it run on Windows? | Cross-platform builds via cloud CI |

---

## Answered Questions

### Should we track Godot master or stable?

**Track stable.** Zylann publishes pre-built godot_voxel binaries for each Godot stable
branch — there are builds for 4.3, 4.4, 4.4.1, 4.5, and 4.6. He also now offers
experimental GDExtension builds (plugin format, no engine recompile needed). Godot's
stable releases come every 3–6 months and maintain backward compatibility within the 4.x
series.

Tracking master would mean compiling both Godot and godot_voxel from source on every
update, dealing with API breakage, and debugging issues that might be Godot's fault vs.
the module's. For an MVP where your goal is validating the idea, that's pure friction. Pin
to Godot 4.6 stable + the matching godot_voxel release and don't look back until you have
a reason to.

### Can the Ryzen 9 7900X iGPU serve as a low-end performance target?

**No — it's far too weak.** The 7900X's integrated graphics is 2 CUs of RDNA 2 (128
shaders). AMD designed it as a display adapter for troubleshooting and basic desktop use,
not gaming. In benchmarks it struggles to hit 17–23 FPS in modern games at 1080p low
settings. It sits roughly in GT 1030 territory.

A GTX 1660 has 1,408 CUDA cores and 6GB of dedicated VRAM — it's roughly 10–15x more
powerful. The 7900X iGPU would be testing "can this run at all?" not "is this performant?"

**Better options for a low-end target:**
- If you already have a spare older GPU (even a GTX 1050 Ti), plug it into a test rig
- A used GTX 1060 6GB or RX 580 runs $40–60 and represents the Steam Hardware Survey's
  low-end floor reasonably well
- Alternatively, use Godot's Forward+ renderer quality settings to simulate lower-end
  GPUs (reduce shadow quality, draw distance, LOD aggressiveness) on your 5090 and
  extrapolate
- The cheapest and most realistic option if you reach that point: a $150–200 used mini PC
  with an AMD APU (Ryzen 5 5600G or 7600, which have real iGPUs with 6–8 CUs)

For v0.0 validation, don't worry about this at all. Test on your 5090 and optimize later.

---

## Phase 0: Foundation (Week 1)
**Goal:** Walking around a procedural voxel world with basic physics.
**Version target:** 0.0

### Tasks
- Set up Godot 4.6 project with godot_voxel (use pre-built binary or GDExtension)
- Configure VoxelTerrain node with VoxelGeneratorGraph or VoxelGeneratorScript
- Basic noise-driven terrain (2–3 octaves of OpenSimplex)
- First-person character controller with gravity and collision against voxel mesh
- Basic camera, movement, jumping
- Day/night cycle (DirectionalLight3D rotation, simple sky shader)

### Claude Code leverage: High
Project scaffolding, character controller boilerplate, noise parameter setup.

### Key decisions
- **Meshing:** Start with VoxelMesherTransvoxel (smooth terrain). This is the "better
  than heightmap" visual argument.
- **Chunk size:** 16³ or 32³. Start with 16³ for faster iteration.
- **LOD levels:** godot_voxel handles this; configure 4–5 levels.

### Risk
Getting godot_voxel working cleanly. Budget a half-day. The pre-built binaries should
make this painless compared to compiling from source.

### Done when
You can walk across an infinite procedural landscape with hills, and fall off cliffs.

---

## Phase 2 (moved up): Terrain Modification (Week 2)
**Goal:** Dig, flatten, raise terrain with tools.
**Version target:** 0.0

### Why this comes before biomes
For the 0.0 validation ("is this as good an idea as I think it is?"), you need to feel
terrain modification before you need pretty biomes. Can you dig a cave? Does it feel
right? That question matters more than whether the meadow transitions nicely to the forest.

### Tasks
- Voxel editing API: sphere/box brush that modifies VoxelBuffer SDF values
- Dig (reduce SDF), fill (increase SDF), flatten (set to plane)
- Visual feedback: crosshair raycast showing edit preview
- Tool system foundation: equip tool → determines edit mode and parameters
- Terrain modification persistence (godot_voxel built-in chunk save/load)
- Particle effects on terrain edit (dust, debris)
- Vertical flattening prototype: create a sheer face in rock (SDF operation that
  sets a vertical plane)

### Claude Code leverage: Very high
SDF brush math is well-documented and pattern-heavy.

### Key decisions
- **SDF editing** gives smooth, natural terrain modification — a huge visual win over
  Valheim's crude flatten/raise.
- **Vertical flattening** is an SDF plane intersection operation. For the prototype, it
  can be instant. The "takes time based on material and skill" mechanic is a gameplay
  layer added later (v0.1).

### Risk
Low. godot_voxel's editing API is mature. Main challenge is remeshing delay feel.

### Done when
You can dig a tunnel into a hillside, carve out a room, build a mound, and cut a sheer
vertical face in a rock wall.

---

## Phase 5 (moved up): Building System (Weeks 3–5)
**Goal:** Place structures that integrate with voxel terrain.
**Version target:** 0.0

### This is the thesis defense. Budget accordingly.

### Tasks
- **Hybrid building approach:**
  - Voxel building: place/remove material voxels (walls, floors from terrain material)
  - Prefab building: parametric rectangular Parts (board, plank, stud, beam) with
    multi-axis 90° rotation
- Ghost preview showing placement before confirming
- **Structural integrity system (the killer feature):**
  - Every voxel and prefab piece has a support value
  - Support propagates from ground contact upward, weakening with material decay
  - Material-dependent: stone supports more than wood, wood more than dirt
  - Color-coded visual feedback (blue → green → yellow → orange → red → collapse),
    same system for terrain AND player structures
  - **Cave ceilings follow the same rules:** when terrain is dug, the exposed cells
    register with the integrity system; unsupported spans show strain colors and
    eventually collapse. Reinforcing with pillars (Parts) restores support.
- Voxel-to-prefab interface (SDF seam matching, Option A2): Parts write matching SDF
  samples into their footprint cells so the Transvoxel mesher produces a clean
  surface continuous with surrounding terrain.

### Deferred to v0.1 (not required for the thesis defense)
- **SDF seam matching (Option A2)** — originally listed as a Phase 5 task; deferred
  after the v0.0 build hit a resolution mismatch. Our parts are sub-cell (thinnest
  axes 0.012–0.15m, voxel cells 1m), so writing per-cell SDF samples can't represent
  a thin board accurately — the visible "seam" between part mesh and Transvoxel
  terrain mesh is a rendering-resolution problem, not an integrity-system problem.
  The right v0.1 answer is probably **physics-driven part-vs-terrain interaction**:
  a buried beam either breaks under load or pushes the dirt aside, depending on
  relative material strength. That pairs naturally with the load-propagation pass
  and falling-damage work, all of which want the same "parts and terrain are
  governed by one physical-strength model" thinking.
- **Sub-assemblies and planning mode** — Dwarf-Fortress-style selection of existing
  structures into reusable assemblies, plus a planning mode where build orders queue
  and are executed step-by-step (with physics tested at each step). Needs UI work.
  Autonomous helpers to execute plans come later still.
- **Free-form placement physics** — placing a Part at an arbitrary position/rotation
  and letting physics determine whether it settles into construction or falls. The
  honest "drop a board, it falls if unsupported" model. Current grid-aligned +
  validate-and-commit placement is enough to demonstrate the thesis.
- **Snap point UI** — `Schematic.snap_points` data structure exists; the
  selection/preview UI for hand-authoring and connecting via Joints is v0.1.
- **Building piece catalog with joinery** — door frames, stairs, roof angles, etc.
  Current rectangular Parts (board/plank/stud/beam) are enough for the cave
  reinforcement demo. Specialised pieces with mate-only-with constraints are v0.1.
- **Workbench radius** — Valheim convention for gating progression; doesn't
  validate voxel-first design. Belongs to the survival loop (v0.9).

### Claude Code leverage: Moderate
Snap logic and ghost preview are well-patterned. Structural integrity is algorithmic
(flood fill from ground with material-weighted propagation). The terrain integration is
novel and needs manual iteration.

### Key decisions
- **Unified structural integrity** is the core innovation. The same algorithm that decides
  whether your wooden roof is supported also decides whether a cave ceiling stays up. One
  system, one visual language, one set of rules. This is the thing that makes people say
  "oh, THAT'S why you'd use voxels."
- **Two building modes:** Voxel mode (free-form sculpting) and Prefab mode (structured
  snap pieces). Voxel mode is unique to this engine.
- **Cave reinforcement:** When you mine into rock, the exposed ceiling gets evaluated for
  structural support. If the span is too wide, it starts showing yellow/red. Place a
  pillar and it turns green. This makes mining a spatial engineering puzzle, not just
  "click rock, get ore."
- **Material angle of repose (simplified for 0.0):** Dirt and sand voxels above a certain
  slope angle will "slump" — converting to a physics object that settles. For 0.0, this
  can be a simple threshold check on exposed faces. Full angle-of-repose simulation with
  material consistency is v0.1.
- **Player-position safety is a construction-mode problem, not a scaffolding patch.**
  The placeholder fill/dig/flatten verbs can drop the player through the world: any
  *additive* terrain edit (fill, vertical flatten, default-normal flatten) can place a
  solid voxel where the player stands or bury their floor. The scaffolding has a cheap
  edit-driven fix (`_push_player_above_terrain` scans the player's column and re-seats
  them), but the *real* answer belongs here: when construction mode replaces those verbs,
  "can a build action place a voxel where the player is" must be an explicit design
  decision. Options to weigh: lower-only semantics for some tools, a build-time collision
  check that refuses or displaces, or treating "push the player" as part of the place
  operation. The insight that generalizes: *subtractive-only editing structurally cannot
  cause fall-through; additive editing always can.* Don't rediscover this — design for it.
- **Terrain operations should fail honest, not fake a surface.** When a terrain op can't
  cleanly do the intended thing, it should produce truthful voxel data — even if that
  means opening a void — rather than faking a result. Example: a horizontal flatten that
  can't lower cleanly because there's material above the cut should *open a small cave*,
  not invent a floor. This is thesis-consistent: the whole argument for voxels over a
  heightmap is that the world is honest geometry, not trickery (Valheim's flatten fakes
  things; ours shouldn't). May generalize into a principle governing all terrain ops —
  worth holding as a design stance going into the construction-mode work.

### Risk
This is where the project sings or stalls. The voxel-prefab interface (a door frame flush
in a voxel wall that merges with the hillside) is genuinely novel. Budget the full 3 weeks
and be prepared to simplify. Fallback: prefab-only building (like Valheim) still works.

### Done when
**The killer demo:** you can dig a wide cave into a hillside and watch the ceiling cells
shift from blue through yellow toward red as unsupported span exceeds the material's
decay budget. Before the strain timer expires, you place wooden beams as pillars,
watch the ceiling's support recover, and continue digging. If you fail to reinforce,
the unsupported section flood-fills into a falling RigidBody3D.

**Distribution:** v0.0 ships as published source (CC BY-SA 4.0) plus Linux, macOS,
and Windows playtester binaries. The thesis defense is *the working code itself* —
no recorded demo, no trailer; the project's open-source release is the artifact
that lets people verify the claim independently.

The "house carved into hillside" framing from earlier drafts is descriptive of the
*aesthetic* but isn't the thesis-defense demo. The cave-integrity loop is. A clean
voxel-to-prefab visual seam was once on this phase; it moved to v0.1+ once sub-cell
parts revealed that SDF samples-per-cell can't represent thin features. See the
deferred list above.

---

## v0.0 Checkpoint: "Is This As Good An Idea As I Think It Is?"

At this point (~5 weeks part-time), you have:
- Infinite procedural terrain you can walk across
- Real terrain modification (dig, fill, flatten, vertical cuts)
- Building that integrates seamlessly with terrain
- Unified structural integrity (the killer feature demo)
- Cave reinforcement gameplay

**No** biomes, resources, inventory, crafting, enemies, or survival loop. This is
deliberately a tech demo, not a game. But it answers the fundamental question: does the
voxel approach deliver on its architectural promises?

If yes → proceed to v0.0.1, then v0.1.
If the structural integrity is too computationally expensive, or the voxel-prefab seam
looks bad, or the terrain modification feels worse than Valheim's → you've spent 5 weeks
instead of 5 months finding out.

---

## v0.0.1: Persistence as Replayable History
**Goal:** Save and load world state — and the operations that produced it.
**Version target:** 0.0.1

### Why this is interesting, not just necessary

A naive save system serializes the current state and reloads it. That's fine for shipping
a game, but it's a missed opportunity for a project whose thesis is *the world is honest
geometry produced by honest operations*. If every terrain edit and part placement is
already a discrete `Action` (validated, then executed), the save file can be the
**journal of actions that produced the current world** — not just a snapshot of the
result.

This is the Quake `.dem` model: a demo file is just the sequence of inputs the engine
replays to reproduce the game state. Same idea here, scaled to world-mutating operations
instead of input events. The save file is both:

- A **state restore** mechanism for normal save/load (replay all actions, or restore
  from a periodic snapshot + tail of actions since the snapshot)
- A **bug reproduction** artifact: a player files a bug, attaches the save, you replay
  it step-by-step and watch the failure happen. No "can you remember what you did?"
- A **debugging tool**: step forward and backward through the action history with the
  integrity system computing live. Watch the strain gradient develop, see exactly which
  action caused a collapse, identify off-by-one or propagation bugs by their visual
  signature.
- A **test harness foundation**: replay a known sequence as a regression test. If the
  cave-integrity demo ever stops behaving correctly, the failing replay is the bug
  report.

The thesis-consistency argument: the world is geometry produced by operations on
geometry. Saving the operations rather than just the result is more honest. It also
means a save file is portable across builds in a way a state snapshot isn't — as long
as the action semantics stay stable, a save from yesterday's build replays correctly
on today's.

### Tasks

- Serialise the `Action` history: every executed action records its type and parameters
  in an append-only journal
- Periodic state snapshots (every N actions or M seconds) so replay-from-zero isn't
  required on every load
- Save format: snapshot + journal tail since snapshot. Versioned, with an action-schema
  version number so old saves can be detected and either replayed under their original
  semantics or rejected cleanly
- Load: restore from snapshot, then replay journal tail with the integrity system
  computing live (or fast-forwarded if the integrity state is part of the snapshot)
- Debug controls: pause replay, step forward/back one action at a time, scrub to a
  timestamp
- godot_voxel chunk persistence integration: the SDF state is part of the snapshot,
  not the journal (journal records the action that mutated SDF, snapshot records the
  SDF result)
- Save UI: at minimum a hotkey for quicksave/quickload; full UI deferred to v0.9

### Key decisions

- **Action serialisation format.** Each Action class knows how to serialise itself. The
  `Action` base class grows `serialise() -> Dictionary` and a static `deserialise(d) ->
  Action`. Keep it simple — strings for action type, primitive values for parameters.
- **Snapshot cadence.** Tunable. Probably every 30 seconds or every 50 actions for v0.0.1,
  optimise later if load times are bad.
- **Action schema versioning is non-negotiable.** Once people start saving worlds, an
  action-semantics change is a save-format break. Version the schema from day one;
  refuse to load saves with unknown schemas; provide a migration path or an honest
  "this save predates the current build, sorry" message. This is the cheapest place
  to put forward-compatibility work and it pays off forever.
- **Determinism.** Replay must be deterministic for the bug-reproduction case to work.
  This means seeded RNG for anything stochastic (collapse direction tie-breaking,
  particle effects if any). Treat non-determinism as a bug from v0.0.1 onward.

### Claude Code leverage: High
Serialisation boilerplate, format versioning, snapshot/journal coordination are
pattern-heavy. The deterministic-replay discipline needs human attention.

### Risk
Determinism is the gotcha. Anything that reads wall-clock time, system RNG, or unordered
dictionary iteration can break replay. Catching these requires a CI test that replays a
known journal and checks the final state matches a recorded hash.

### Done when
You can dig a cave, place beams, watch a collapse, save, quit, reload, and the world is
exactly as you left it — including the in-progress strain timers. You can also replay
the save from zero and watch your session happen in fast-forward, step through one
action at a time, and produce a deterministic state hash.

---

## Phase 1: Biomes & Terrain Character (Weeks 6–7)
**Goal:** The world feels like it has places worth exploring.
**Version target:** 0.1

### Tasks
- Biome system: temperature/moisture noise maps → biome selection
- Minimum 4 biomes: Meadow, Forest, Mountain, Swamp
- Per-biome terrain parameters: amplitude, frequency, base height, cave density
- Cave generation using 3D worm noise (continuous with surface — no loading screens)
- Water plane with basic shader (flat plane at sea level for MVP)
- Scatter system: trees, rocks, bushes (instanced MultiMeshes)
- Biome-appropriate vegetation distribution

### Claude Code leverage: High
Noise composition, biome lookup tables, scatter algorithms.

### Key decisions
- **Cave generation:** 3D Perlin worms or cellular automata carved into the voxel volume.
  Caves ARE the terrain.
- **Trees:** Scene instances on voxel surface, NOT voxel geometry. Use CC0 models.
- **Biome blending:** Smooth transitions via noise interpolation.

### Risk
Performance with thousands of scattered instances. Use godot_voxel's instancing support.

### Done when
Walk from meadow through forest, climb mountain, find cave, walk in (no loading screen),
emerge elsewhere.

---

## Phase 3: Resource Harvesting (Weeks 8–9)
**Goal:** Chop trees, mine rocks, gather materials.
**Version target:** 0.1

### Tasks
- Destructible resource nodes: trees, rocks, ore deposits, bushes
- **Continuous work actions (not click-spam):**
  - Select tree → choose fall direction → initiate → watch avatar make directional cuts
  - Select rock face → specify dig depth → initiate → watch avatar mine and pile debris
  - Interruptible: if a creature attacks, pause task, deal with it, resume
  - Progress bar / animation showing work completion
  - Speed depends on tool quality and material hardness
- Tree falling physics (RigidBody3D, directional based on player choice)
- Resource drops as collectible items
- Item data model: ID, name, icon, stack size, category, weight
- Voxel material types for ore (copper voxel → drops copper when mined)
- Interaction system: raycast → detect → prompt → execute

### Claude Code leverage: Very high
Data modeling, item databases, state machines for continuous work actions.

### Key decisions
- **Continuous actions** are a significant UX improvement over Valheim's click-spam. The
  implementation is a state machine: IDLE → TARGETING → WORKING → INTERRUPTED → RESUMING.
  Claude Code can scaffold this pattern quickly; the tuning (animation timing, camera
  behavior during work) needs manual feel-testing.
- **Directional tree felling** is a real woodcutting technique (the notch cut). This is
  both more realistic and more engaging than Valheim's "hit tree, tree falls randomly."
- **Voxel material types:** godot_voxel supports material IDs per voxel. Ore IS the
  terrain.

### Risk
Tree physics jank. Keep collision simple, despawn after a few seconds.

### Done when
You can select a tree, choose where it falls, watch your avatar work, pick up wood.
Mine a rock face by specifying depth, get stone and copper ore. Get interrupted by a
creature, fight it, then resume mining where you left off.

---

## Phase 4: Inventory & Crafting (Weeks 10–11)
**Goal:** Manage items, craft new ones at stations.
**Version target:** 0.1

### Tasks
- Grid-based inventory UI with drag-and-drop, stack splitting
- Equipment slots: weapon, tool (minimal)
- Hotbar with number key switching
- Crafting recipe data model (inputs → output + station requirement)
- Placeable stations: workbench, forge, cooking fire
- Station UI: available recipes filtered by station type
- Recipe discovery: all visible, greyed until you have materials
- 3-tier progression: hand-craft basics → workbench tools → forge metals
- Item tooltips

### Claude Code leverage: Extremely high
UI-heavy, data-driven, pattern-heavy. Claude Code will demolish this phase.

### Key decisions
- **Data-driven recipes** (JSON or Godot Resources). Modding-friendly from day one.
- **3 crafting tiers max** for 0.1. Don't go deeper or you'll spend weeks on balance.

### Risk
UI polish time sink. Functional but ugly is fine. Colored rectangles with text labels.

### Done when
Open inventory, see gathered wood/stone, walk to workbench, craft pickaxe, equip it,
mine faster than bare hands.

---

## v0.1 Checkpoint: "Can I Make It Fun/Performant?"

At this point (~11 weeks part-time from start), you have everything from v0.0 plus biomes,
resource gathering with continuous work actions, inventory, crafting, and the full material
loop. No enemies or survival pressure yet, but it's a playable sandbox.

**Performance validation:** Profile on your 5090, then test with aggressive quality
reduction to simulate lower-end hardware. Key metrics: chunk meshing time, frame budget
at various draw distances, structural integrity computation cost.

### Forward-looking design direction for v0.1: honest physics interaction

The v0.0 deferred list (see Phase 5) clustered several items — SDF seam matching,
load propagation, falling damage, fallen-dirt-as-terrain — that initially looked
like separate features but resolve to a single design statement:

> Transient physics state and persistent terrain state should be able to become
> each other, governed by relative material strength.

A falling RigidBody3D of dirt that comes to rest should be able to rejoin the SDF
as terrain. A beam under enough load should snap. A buried beam, depending on
relative strength, should either break under the dirt or displace the dirt aside.
The SDF seam between part and terrain isn't a rendering problem to be hidden —
it's a contact between two materials with strength properties, and what happens
at that contact is part of the physics. This is the natural extension of
"material physics matter" from the Design Principles, and it's the v0.1 design
direction that ties the deferred items together.

---

## Phases Beyond v0.1 (Scoped But Not Scheduled)

### v0.2: "Can I Make It Pretty?"

- Art direction pass (establish visual identity distinct from Valheim)
- Terrain shaders: triplanar texturing, moss/snow accumulation
- Lighting and atmosphere per biome
- Building piece models (replace programmer art)
- Sound design: ambient biomes, footsteps, chopping, mining, structural creaking
- Tree/vegetation shader wind
- Water shader (reflections, shoreline foam)
- UI overhaul

### v0.9: "Can I Make It Into A Real Product?"

- **Multiplayer** (Godot 4's multiplayer API + voxel chunk sync)
- Survival loop: health, stamina, hunger, food buffs, comfort system
- Enemy AI and combat (see Pathfinding section below)
- Boss encounters as progression gates
- Procedural dungeons (generated cave complexes — no loading screens)
- Building material tiers (wood → stone → iron-reinforced)
- Death, respawn, bed placement
- Settings menu, keybinding, accessibility

### v1.0: "Will People Pay For It On Steam?"

- Steam integration (cloud saves, achievements, multiplayer matchmaking)
- Tutorial / onboarding
- Content depth (enough biomes, enemies, bosses, recipes for 40+ hours)
- QA across Linux and macOS
- Open-source release (game code), Steam for value-added features

### v1.1: "Can I Make It Run On Windows?"

- Cross-compilation via cloud CI (GitHub Actions with Windows runners)
- Windows-specific testing (graphics driver quirks, filesystem paths)
- Only worthwhile if Linux/Mac sales demonstrate demand

---

## Known Hard Problems

### Mob Pathfinding on Voxel Terrain

This is legitimately one of the hardest problems in the project. Heightmap games generate
a 2D navmesh and call it done. Voxel terrain is 3D, deformable, and has caves — navmesh
generation is expensive and invalidated every time terrain changes.

**Approaches, from simplest to most correct:**

1. **Raycast steering (v0.9 starting point):** Enemies cast rays ahead and to the sides,
   steer away from obstacles, chase player by direction. No navmesh at all. Works for
   simple melee rushers in open terrain. Fails in caves and around structures.

2. **2.5D navmesh per chunk:** Generate a walkable surface mesh from the voxel data
   (essentially a heightmap extracted from the voxel volume for each chunk). Recompute
   when chunks are modified. Handles surface navigation well but doesn't help with
   multi-level cave navigation.

3. **3D navigation grid:** A coarse voxel grid (2m resolution) marking walkable,
   climbable, and blocked cells. A* pathfinding on this grid. Handles caves and
   multi-level structures. Expensive to compute but can be done incrementally (only
   recompute modified chunks).

4. **Hierarchical pathfinding (HPA*):** Pre-compute region connectivity at a coarse level,
   then fine-path within regions. This is what Dwarf Fortress eventually moved toward.
   Good for large worlds but complex to implement.

**Recommendation:** Start with option 1 for outdoor enemies, option 3 for dungeon
enemies. Claude Code can generate the A* implementation and grid extraction; the hard part
is making movement LOOK natural (smoothing paths, avoiding jitter, handling slopes). Budget
significant time for feel-testing.

**The "does it look right" problem** is real and can't be automated. Record video of enemy
movement, watch at 0.5x speed, identify what looks wrong. Common issues: path oscillation,
inability to handle ledges, getting stuck on terrain features, unnatural turning.

### CPU-Bound Architecture and GPU Offload

The current architecture runs all the interesting work — structural integrity
propagation, part support recomputation, collapse detection — on the main thread.
godot_voxel meshes on background threads, so chunk meshing isn't the bottleneck, but
our systems are. Heavy digging already produces observable frame drops in v0.0,
and the load gets worse as the tracked region grows.

**Two open questions, ordered by likelihood of being the right move:**

1. **More threads first.** Structural integrity propagation is a fixpoint over a
   dirty queue. The natural parallel structure is "work-steal from the queue,"
   with care taken around the shared `voxel_data` dictionary. Part recomputation
   is a topological sort followed by an embarrassingly parallel pass within each
   level. Both are tractable on CPU threads and probably enough for v0.1's
   performance target.

2. **GPU offload via compute shaders or OpenCL.** Tempting because the integrity
   field is structurally a 3D scalar field with local update rules — the kind of
   thing GPUs eat for breakfast. The catch is that the current algorithm has
   *non-local* dependencies (lazy expansion can chain through ~20 cells of
   untracked terrain), and the part recomputation has explicit ordering (sort
   parts by `placement_y`, then resolve direct supporters). Both could plausibly
   be reformulated to flatten dependencies into independent passes — e.g.,
   pre-expand the tracked region before each propagation step, then run a fixed
   number of Jacobi-style iterations until convergence — but that's a real
   redesign, not a port.

**Recommendation:** Don't pursue GPU offload until threading is exhausted and a
profile points unambiguously at structural integrity as the bottleneck. The
threading path is incremental and reversible; the GPU path is a structural
redesign that fights the algorithm's natural shape. If the GPU path *is* the
right answer, the redesign work (flattening dependencies into independent passes)
is also what makes the threaded version faster, so the threading work isn't
wasted.

**The lurking architectural question:** if and when GPU offload happens, does the
integrity field live on the GPU full-time with periodic CPU readback for game
logic, or does it ping-pong per frame? The answer depends on whether anything
other than the integrity system reads the integrity field. If only the renderer
(via strain-color shaders) and the collapse detector need it, GPU-resident is
fine. If gameplay systems start querying support values, ping-pong gets
expensive. Worth flagging now so we don't accidentally design ourselves into a
ping-pong corner.

### Planet-Scale World (Post-MVP)

The dream: sail across a seemingly infinite ocean for in-game months and discover a new
continent, on an Earth-like spherical planet.

**This is achievable but requires architectural decisions made early:**

- **godot_voxel "double" builds:** Zylann publishes builds with large world coordinate
  support (64-bit floats). Use these from day one even if you don't need them yet. No
  cost, prevents a painful migration later.
- **Cube-sphere projection:** Map 6 cube faces to a sphere surface. Each face is a
  flat voxel world internally, with projection distortion handled at the rendering layer.
  This is how No Man's Sky, Minecraft-inspired planet mods, and various space games do it.
- **Tectonic simulation (generation-time only):** Generate plate boundaries, mountain
  ranges, and ocean basins from tectonic rules, then use these as inputs to the biome
  noise functions. Doesn't need to be real-time — run it once during world creation.
- **Ocean:** The hardest part for a voxel engine. Heightmap engines get ocean "for free"
  (it's just another height value). Voxel oceans need either a water surface plane with
  wave simulation (visual only, not voxel) or actual fluid voxels (expensive). For sailing,
  a shader-based ocean surface with buoyancy physics is the pragmatic choice.

**Key early decision:** Use the godot_voxel double-precision build. Everything else can
wait until post-MVP, but the coordinate precision cannot be retrofitted.

### World Setting (Creative, Not Technical)

Needs to be iron-age-and-then-some but distinctly NOT Norse mythology or any single
existing mythology. Some directions worth exploring:

- An original mythology that synthesizes elements from underrepresented traditions
- A post-collapse setting where iron-age technology is what remains after something bigger
- A world where the voxel nature is diegetic — the world IS made of discrete matter, and
  the structural integrity rules are laws of physics the inhabitants understand
- Something that makes the cave-reinforcement mechanic feel culturally embedded, not just
  a game mechanic

This deserves its own design document when the time comes.

---

## Continuous Work Actions (Design Detail)

The click-spam replacement for mining and logging:

### Tree Felling
1. Select tree with interaction key
2. UI shows tree info (type, size, estimated resources)
3. Choose fall direction (rotate ghost outline of fallen tree)
4. Confirm → avatar begins notch cut sequence
5. Camera pulls to a comfortable third-person angle during work
6. Progress bar shows completion
7. Tree cracks, falls in chosen direction, impacts ground
8. Logs and branches become collectible
9. If interrupted (damage taken), work pauses; player regains control
10. After dealing with interruption, can resume (progress preserved)

### Mining
1. Select surface with mining tool
2. UI shows material type, hardness
3. Drag to set mining volume (width × height × depth)
4. Confirm → avatar begins mining
5. Debris piles up nearby (collectible resource nodes)
6. Structural integrity evaluates in real-time as material is removed
7. If ceiling integrity drops to red, mining auto-pauses with warning
8. Player can reinforce, then resume
9. If interrupted by creature, work pauses; resume after

### Vertical/Horizontal Smoothing
1. Select surface area to smooth
2. Choose operation: vertical flatten, horizontal flatten, smooth
3. Confirm → avatar works with chisel/tool
4. Duration depends on: material hardness, area size, tool quality, player skill
5. SDF values interpolate toward target surface over the work duration
6. Like a crafting station: start the job, wait, result appears

---

## Architecture Notes

### Architectural Commitments

These patterns emerged during v0.0 implementation and are now load-bearing across the
codebase. They're documented here as design commitments, not just code conventions,
because changing them would mean rewriting most of the world-mutating code. `CLAUDE.md`
documents how to *use* them; this section documents *why they exist*. For mechanism
rationale (in-limbo semantics, pause-correct strain accumulation, seed-vs-expand
asymmetry, etc.), see `docs/architecture.md`.

**Action-as-data with `validate()` then `execute()`.** Every world-mutating operation
— dig, fill, flatten, place-part — is a `RefCounted` subclass of `Action` carrying its
final computed parameters (not raw input). `validate()` returns true only if the
operation can be performed with truthful semantics; `execute()` then performs it.
Targeting logic (raycasting, computing sphere centres) lives at the call site, not
inside the Action. This shape is what makes v0.0.1's history-as-journal feasible: an
Action with a deserialisable parameter set is replayable.

**Refuse-don't-deform.** Actions refuse via `validate()` when constraints can't be met,
rather than silently adjusting to produce *some* result. Extended to physics state via
FillAction's `intersect_shape` check (fills that would overlap a RigidBody3D are
refused, otherwise the body squirts through the world). This is the operational
expression of the thesis-defence design stance: a terrain op that can't cleanly do the
intended thing should produce honest data — even if that means opening a void or
returning failure — rather than faking a result. The Valheim flatten fakes things;
ours doesn't.

**Worklist-fixpoint propagation for terrain support.** `StructuralIntegrity` drains a
FIFO dirty queue at a bounded budget per physics frame. BFS-order is the right shape for
support propagation (changes spread outward from their origin); the shift cost on
typical queue sizes isn't where the time goes. The fixpoint is reached when no
additional dirty cells are produced by recomputation — budget exhaustion just stretches
the fixpoint across multiple frames, it doesn't change the result.

**Per-column bedrock detection.** `_lowest_registered_y: Dictionary[Vector2i, int]`
indexes the lowest registered Y per `(x, z)` column; `_is_bedrock(pos)` returns true
when the column has nothing registered below `pos.y`. Combined with untracked-solid
status, this is what distinguishes *real* bedrock (which grants full support to its
neighbours) from *suspended mass* (which doesn't, even though it's solid in the SDF).
Necessary to prevent floating chunks from blessing the cells above them as supported
after a collapse.

**Lazy expansion bounded by material decay.** When propagation reaches an
untracked-solid neighbour that isn't bedrock, it gets lazy-registered with material
STONE so the algorithm can compute its actual support. Lazy registration is gated on
the current cell's support being above `FALL_THRESHOLD` — cells already at zero won't
seed a chain worth extending. The cascade depth is therefore bounded by the material's
decay budget (~20 cells for STONE), which is the same bound that makes the support
values meaningful.

**Per-cell stack of parts.** Multi-cell rotation can place multiple thin parts in the
same voxel cell. `_cell_to_part: Dictionary[Vector3i, Array[Node3D]]` is therefore a
stack ordered by `placement_y`, and direct-supporter lookup walks the stack to find the
part with the highest `placement_y` below the queried part. Single-part-per-cell would
have been simpler but couldn't represent stacked boards.

**In-limbo semantics for parts.** A part is `in_limbo` when any of its support
dependencies (a supporter Part still in-limbo, or a terrain voxel still dirty) hasn't
settled. Strain accumulation skips while in-limbo, so a transient zero during
propagation doesn't trigger a 3-second countdown that would resolve before expiry.
Without this, every dig near a part triggers spurious collapse timers.

**Data-driven definitions via `.tres`.** Parts (`assets/parts/*.tres`) and Materials
(`assets/materials/*.tres`) live in resource files, not in code. Adding a wood Part or
a new material is a file copy and a parameter tweak. The roadmap originally specified
JSON for this; `.tres` is strictly better in this codebase — it's Godot-native,
editor-discoverable, and avoids a parse step at startup. Anyone who wants JSON can
export from `.tres` as easily as the reverse.

**Facade composition for the structural subsystem.** `StructuralIntegrity` is a thin
`Node` facade composing three `RefCounted` components — `TerrainSupport` (voxel
propagation), `PartSupport` (part recomputation + strain + collapse), `IntegrityDebug`
(debug cubes) — plus `CollapseDetector` as a peer of `TerrainSupport`. Components hold
typed back-references to each other for cross-state lookups (terrain reading parts'
`best_support_at`, parts reading terrain's `voxel_data`); the facade breaks the
`TerrainSupport ↔ PartSupport` cycle in `_exit_tree` so RefCounteds free cleanly.
The split exists because each component owns a chunk of state that maps directly to
"what to save/restore" for v0.0.1 persistence, and because the previous single
500-line script no longer fit a working-memory budget.

**Player composes RefCounted helpers.** The player Node (`scenes/player/player.gd`)
composes five helpers — `PlayerMovement`, `CameraRig`, `BuildState`, `ActionFactories`,
`EditModeCatalog` — each owning one concern. The player keeps input dispatch dicts,
the per-frame orchestration glue, and the `@onready` references that nodes need.
Same pattern as the structural facade and same justification: each file owns one job,
no file blows the size budget, and each helper is independently testable.

**Helper lambdas capture local refs, not `self`.** When a RefCounted class holds an
`Array[Callable]` (e.g. `EditModeCatalog.modes` holding `EditMode` instances whose
make-action and preview lambdas reference instance fields), the implicit `self` capture
forms a cycle: catalog → modes → EditMode → Callable → catalog. The cycle prevents
the RefCounted catalog from freeing on exit and leaks Mesh resources. The fix is to
pass dependencies as parameters into the builder function and let lambdas close over
the locals. See `EditModeCatalog._build_catalog` for the pattern. This is general
across the codebase: when a helper stashes lambdas in a long-lived collection,
prefer local-capture over self-capture.

**Typed records over dict-as-struct.** `VoxelRecord`, `PartData`, `PendingCollapse`,
`PendingFlood` are RefCounted classes with named fields rather than string-keyed
dictionaries. Field access has the same syntax (`rec.support`); the wins are
editor-discoverable types, no string-key duplication, and correctly-typed iteration
variables (a `for x in voxel_data` loop's `x` is `Vector3i`, not `Variant`). Same
reason to convert Materials from a code-defined class to `.tres` files: structured
data beats stringy data when the IDE can help.

### Why godot_voxel

This is the single most important dependency. Without it, the voxel engine alone is 6–12
months. With it you get: chunk-based infinite terrain with LOD, TransVoxel and blocky
meshing, built-in terrain editing (SDF operations), material/texture support per voxel,
chunk streaming and persistence, multithreaded mesh generation.

MIT licensed, actively maintained, releases tracking Godot stable branches.

**Tradeoff:** coupling to a third-party module. If Zylann stops maintaining it, you fork.
Acceptable risk for MVP. The module is C++ with clear interfaces — forkable by someone
with your experience if necessary.

**Use the double-precision build** from the start for planet-scale future-proofing.

### Performance Budget (Targeting 60fps on GTX 1660-class)

| System | Budget | Strategy |
|--------|--------|----------|
| Voxel meshing | 8ms max | godot_voxel threading; tune chunk distance |
| Structural integrity | 2ms | Compute on modification, not per-frame; cache results |
| Scattering | 4ms | MultiMeshInstance3D, frustum culling, LOD |
| Physics | 4ms | Simplified colliders, sleep distant bodies |
| AI | 2ms | Max 20 active enemies, simple state machines |
| Rendering | 12ms | Forward+, limited shadows, no volumetric fog |
| Game logic | 2ms | Event-driven crafting/inventory |

### Folder Structure

See `CLAUDE.md` for the current scene graph, script organisation, and architectural
conventions. That doc is maintained as the authoritative description of where code
lives and how it's structured; duplicating it here would just create drift.

---

## CC0 Asset Sources

| Source | What | License |
|--------|------|---------|
| Kenney.nl | Low-poly models, UI, sounds | CC0 |
| Quaternius | Characters, nature, buildings | CC0 |
| OpenGameArt.org | Mixed (filter CC0) | Varies |
| Freesound.org | Sound effects (filter CC0) | Varies |
| Ambientcg.com | PBR textures for terrain | CC0 |

---

## The Elevator Pitch

> Valheim chose a heightmap engine in 2018 and has spent 7+ years working around its
> limitations: loading screens for caves, floating buildings, fake terrain modification,
> no overhangs. This project proves that a voxel engine — built today with modern tools
> and AI-assisted development — delivers the same core gameplay without those compromises.
>
> Your house grows out of the mountain. Your mine connects to a natural cave. Dig too
> wide and the ceiling warns you before it collapses. Reinforce it with pillars and keep
> going. The world is one continuous space, governed by one set of physical rules.

---

## Appendix A: Competitive Landscape

### Enshrouded (Keen Games, Early Access January 2024)

The closest competitor to this project's vision. Keen Games built a proprietary voxel
engine for a survival-action RPG set in a voxel-based continent. The building and
terraforming are genuinely impressive — players can carve stairs into cliffs, dig
underground bases, and shape terrain with fine-grained control.

**What they got right:**
- Proved the market wants voxel-based survival with real terrain modification
- Building system that feels artistic and precise, not just functional
- Voxel-based world that looks realistic, not blocky
- Solid commercial success in early access

**Where they compromised (and where we differentiate):**
- Terrain modifications outside your base area reset to their original state. This is
  the single biggest player complaint. The stated reason is save data management — a
  solved problem that Minecraft handled 15 years ago with chunk diffs. A terabyte of SSD
  costs $150. This decision sacrifices immersion for engineering convenience.
- No structural integrity system. You can build floating structures in midair. This
  removes the engineering-puzzle aspect of construction entirely.
- Loading screens still exist for certain transitions.
- No cave reinforcement mechanics — caves are static geometry.

**Our direct advantages over Enshrouded:**
1. Persistent terrain modification everywhere, not just near your base
2. Unified structural integrity for terrain AND structures
3. Cave reinforcement as a gameplay mechanic
4. Continuous work actions instead of click-spam
5. Material physics (angle of repose, structural properties)

### Deep Rock Galactic (Ghost Ship Games, 2020)

Not a survival game, but the gold standard for "terrain destruction that feels good."
Fully destructible procedurally generated cave systems where digging is a core traversal
and combat mechanic. Sold over 8 million copies. Proves that voxel terrain deformation
can be performant, satisfying, and central to a game loop.

**What to learn:** The *feel* of their terrain destruction — the sound design, particle
effects, and immediate visual feedback when you drill through rock. Study their chunk
meshing performance. Their terrain is ephemeral (per-mission), so they never had to solve
persistence, but their real-time deformation is best-in-class.

### Teardown (Tuxedo Labs, 2022)

The gold standard for voxel structural simulation. Every object in the world is made of
voxels with physical properties. Structures collapse realistically when supports are
removed. Not a survival game — it's a heist/puzzle game — but its physics engine is
proof that structural integrity simulation at game-scale is achievable and fun.

**What to learn:** Their structural simulation algorithm. When you remove voxels, connected
components are evaluated and unsupported sections become physics objects. This is exactly
the behavior we want for cave ceilings and unsupported building sections.

### Hytale (Hypixel Studios, Early Access January 2026)

A cautionary tale more than a competitor. See Appendix B for the full case study. Blocky
Minecraft-style voxels with excellent world generation and modding tools. After $100M and
10 years of development, it shipped on a four-year-old legacy build after the "improved"
engine was abandoned. Its world generation system is worth studying; its development
history is worth studying harder.

### VoxelFarm (Engine/Middleware)

Not a game but an engine — the most technically ambitious voxel terrain system in
existence. Smooth SDF terrain with real-time editing, LOD, and procedural generation.
Originally targeted games but has pivoted to architecture, simulation, and GIS products.
This pivot likely reflects the game industry's reluctance to fund voxel-first game
development despite the technology being ready.

**The gap VoxelFarm's pivot reveals:** The tech exists. The market demand exists (see
Enshrouded's sales, DRG's 8M copies). What's missing is someone willing to build a
game on voxel-first principles without either (a) compromising on persistence and physics
(Enshrouded) or (b) drowning in scope creep (Hytale). That's the gap this project fills.

### Alientrap (Unannounced, In Development ~2025)

The studio behind Apotheon and Capsized is building an unannounced multiplayer survival
game described as "Astroneer-like setting, Teardown voxel physics, in a Valheim-like
online multiplayer survival game." Tech demos show voxel physics with gravity and
connected-object simulation. Worth monitoring — this is the closest anyone has come to
announcing a project in our exact design space. Their Astroneer-like sci-fi setting means
minimal thematic overlap with our iron-age direction.

### The Competitive Summary

Nobody has shipped a persistent open-world survival game with:
- Real volumetric terrain that never resets
- Unified structural integrity for terrain and construction
- Cave reinforcement as gameplay
- Seamless underground-to-surface continuity (no loading screens)

Enshrouded came closest and punted on persistence and physics. Deep Rock nailed the feel
but isn't persistent. Teardown nailed the physics but isn't open-world survival. The
intersection of all three is unoccupied.

---

## Appendix B: The Hytale Case Study — How to Burn $100M and Ship Nothing

### Timeline

- **2015–2018:** Small team of Minecraft modders builds a working voxel game engine in
  C#/Java. By 2018, the game is nearly ready for launch. Announcement trailer gets 60
  million views.
- **2020:** Riot Games acquires Hypixel Studios. Funding secured, scope begins expanding.
- **2022:** Decision to rewrite the entire engine in C++ for simultaneous cross-platform
  launch (PC, mobile, console). Seven years of working code is effectively thrown away.
- **2022–2025:** Engine rewrite consumes all development momentum. Working features are
  scrapped and rebuilt from scratch, often with worse results. Veteran developers watch
  their code get replaced. Key people leave under stress.
- **June 2025:** Riot cancels Hytale after $100M+ spent. Studio closure announced.
- **November 2025:** Original founder Simon Collins-Laflamme buys back the IP with
  personal funds. Rehires 30 developers. Reverts to the four-year-old legacy build.
- **January 2026:** Ships early access in eight weeks. It's rough but playable. Critics
  note that Riot probably could have shipped this years ago.

### What Actually Went Wrong

It was not a technology problem. It was not a talent problem. It was an organizational
and decision-making problem.

**1. The engine rewrite was unjustified.**
The original C#/Java engine worked. It produced the trailer that got 60 million views. The
rewrite was driven by Riot's desire for simultaneous cross-platform launch — a business
requirement, not a technical necessity. The right answer was: ship on PC first, port later.
The founders eventually proved this by shipping the legacy build in eight weeks.

**2. New leadership disrespected existing expertise.**
The former IT lead's assessment: "What could possibly go wrong when you hire new
leadership that thinks the original team is incompetent? The whole project ends up going in
circles until it dies." Producers with "real game industry experience" were brought in and
proceeded to rewrite systems that already worked, not because they were broken but because
the new people hadn't built them.

**3. Scope creep was driven by corporate metrics, not player needs.**
Riot wanted a "forever platform" on every device simultaneously. The original team wanted
to ship a moddable PC sandbox game. The original team was right. The market they were
targeting (Minecraft's audience) lives on PC. Mobile and console could have followed.

**4. Perfectionism replaced shipping.**
The rewritten engine was perpetually "almost ready" but never playable. Meanwhile, the
legacy build sat in a Git repository, functional but abandoned. The team optimized for
the long game instead of the fastest path to a playable release. Three years of
infrastructure work produced nothing players could touch.

**5. Money made things worse, not better.**
$100M funded a 150-person team that produced less than the original 30-person team had in
2018. More people meant more coordination overhead, more competing visions, more process,
and less velocity. The founder's eventual solution — buy it back, rehire 30 people, ship
in eight weeks — proves that a focused small team outperforms a bloated one.

### Lessons for This Project

These are not abstract principles. They are specific engineering decisions:

**Ship the working thing.** The v0.0 checkpoint exists to prevent Hytale syndrome. If
Phase 0 + 2 + 5 produce a playable tech demo in 5 weeks, ship it. Show it to people.
Get feedback. Do not retreat into infrastructure work.

**Never rewrite to satisfy a hypothetical future requirement.** Godot 4.6 + godot_voxel
is good enough. If it needs to be better someday, you'll know specifically why, and you
can make targeted improvements. A ground-up rewrite is never the answer for a solo
developer or a small team.

**PC first. Everything else later.** Linux first, macOS second, Windows when there's
demand. Cross-platform is a distribution problem, not an architecture problem. Godot
handles the engine layer; you handle the game.

**Stay solo (or very small) as long as possible.** Every person added to a project
introduces communication overhead and competing vision. Claude Code is a force multiplier
that doesn't argue about architecture. A solo developer with AI assistance and clear vision
will outpace a confused team of 150 every time.

**Data-driven design enables future flexibility without premature engineering.** Items,
recipes, biomes, and materials defined in JSON files. Mod support is a side effect of good
architecture, not a feature you build. This is the right kind of future-proofing — it
costs nothing now and pays off later.

**The engineer was right: "It's simple, just X."** Collins-Laflamme proved this. The game
was there in 2018. It was there in the legacy build in 2025. It took eight weeks to dust
it off and ship it. Sometimes when an engineer says "it's simple, just ship the thing we
already have," they are correct, and the people adding complexity are the ones who need to
justify their position — not the other way around.
