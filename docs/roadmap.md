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

6. **The voxel grid is a spatial database, not just a renderable surface.** SDF and
   material are channels in this database. Temperature, moisture, pressure, momentum,
   and other 3D-continuous quantities can be additional channels — possibly at different
   resolutions per channel. The grid stores *what the matter is and what's happening in
   the volume*. Roles, identities, and gameplay concepts (this is a building, this is
   a load-bearing wall, this is a load-bearing wall belonging to player X's house) live
   in sidecar indexes maintained by other systems, keyed by voxel coordinate.

7. **Terrain operations should fail honest, not fake a surface.** When a terrain op can't
   cleanly do the intended thing, it should produce truthful voxel data — even if that
   means opening a void — rather than faking a result. The whole argument for voxels over
   a heightmap is that the world is honest geometry, not trickery.

---

## Version Strategy

| Version | Question it answers | Roughly maps to |
|---------|-------------------|-----------------|
| 0.0 | Is this as good of an idea as I think it is? | Phases 0, 2, 5 (fast path) |
| 0.1 | Can I make it fun/performant? | Phases 1, 3, 4, 5.5 (filling in the gameplay) |
| 0.2 | Can I make it pretty? | Art pass, shader work, audio, polish, fracture fidelity |
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

### Are voxels the right primitive, or are we picking a perfect hammer?

**Voxels are right for the hardest part of the problem (continuous terrain, no loading
screens, real modification, caves as first-class spaces) and adequate for the rest via
a hybrid approach.** The alternatives surveyed:

- **Tetrahedral / unstructured meshes:** Physically accurate, supports arbitrary topology.
  Tooling is decades behind dense voxel engines; no shippable game uses these.
- **CSG trees:** Lossless and semantically rich, but pathological after thousands of
  edits. Prototyping tool, not a shipping representation.
- **Sparse voxel octrees / OpenVDB-style structures:** Where godot_voxel will probably go
  long-term for planet-scale work. Dynamic editing is harder than dense chunks; tooling
  is research-grade.
- **B-rep (CAD-style):** Perfect for buildings, catastrophic for terrain.
- **Hybrid (voxels for terrain, mesh for construction):** What this project actually does.
  Terrain is voxels with SDF; player-placed prefab pieces are traditional rigid bodies
  with collision meshes; the structural integrity system is the connective tissue that
  lets them speak the same language ("how supported is this thing, regardless of what
  kind of thing it is").

The instinct to worry about "what if a voxel is two types of cell?" is a category error.
The voxel stores *what the matter is*. Whether that matter is *part of a building* or
*part of a load-bearing structure* is a role, not a property — and roles live in sidecar
indexes maintained by their owning systems. This is the same pattern as ECS: entities
don't carry their roles, the role-systems carry indexes of which entities they care about.

---

## Phase 0: Foundation (Week 1)
**Goal:** Walking around a procedural voxel world with basic physics.
**Version target:** 0.0
**Status:** Complete.

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
**Status:** Complete.

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
**Status:** Complete for v0.0 thesis defense. Deferred items moved to Phase 5.5.

### This was the thesis defense. Budget accordingly.

### Tasks
- **Hybrid building approach:**
  - Voxel building: place/remove material voxels (walls, floors from terrain material)
  - Prefab building: snap-together pieces for doors, roofs, stairs
- Building piece catalog (MVP): wall, floor, roof (45°), stairs, door frame
- Snap point system: pieces detect and align to adjacent pieces
- Ghost preview showing placement before confirming
- **Structural integrity system (the killer feature):**
  - Every voxel and prefab piece has a support value
  - Support propagates from ground contact upward, weakening with distance
  - Material-dependent: stone supports more than wood, wood more than dirt
  - Color-coded visual feedback (green → yellow → red → collapse), same system for
    terrain AND player structures
  - Cave ceilings follow the same rules: unsupported spans collapse over time
  - Player can reinforce caves with wooden beams or stone pillars
- Voxel-to-prefab interface: prefab pieces anchor to voxel terrain seamlessly
- Foundation carving: building foundations carve into terrain voxels automatically
- Workbench radius requirement for building

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

### Risk
This is where the project sings or stalls. The voxel-prefab interface (a door frame flush
in a voxel wall that merges with the hillside) is genuinely novel. Budget the full 3 weeks
and be prepared to simplify. Fallback: prefab-only building (like Valheim) still works.

### Done when
You can build a house partially carved into a hillside, with voxel stone walls that blend
into the rock face, a door, a roof, and visual feedback showing structural integrity. You
can dig a wide cave and watch the ceiling turn yellow, then place pillars to stabilize it.

---

## v0.0 Checkpoint: "Is This As Good An Idea As I Think It Is?"

**Answered: yes.** The thesis is largely architectural, and architectural theses are
defensible by argument. The conversation around the design — the role-vs-matter
distinction, the event-bus pattern, the multi-grid approach for vehicles, the
fracture-as-mesh-extraction insight — has stress-tested the architecture and surfaced
plausible answers to every seam found so far. The v0.0 work proved out the foundation;
the design conversation proved out the path forward.

At this point (~5 weeks part-time), you have:
- Infinite procedural terrain you can walk across
- Real terrain modification (dig, fill, flatten, vertical cuts)
- Building that integrates seamlessly with terrain
- Unified structural integrity (the killer feature demo)
- Cave reinforcement gameplay

**No** biomes, resources, inventory, crafting, enemies, or survival loop. This is
deliberately a tech demo, not a game. Proceed to v0.1.

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

## Phase 5.5: Architectural Maturation (Interleaved with 1, 3, 4)
**Goal:** Replace v0.0's direct couplings with the architecture needed for the rest of v0.1.
**Version target:** 0.1

This phase contains the items we deferred from Phase 5 plus the architectural insights
from the v0.0 retrospective. It's deliberately split into independent sub-phases so each
can be tackled when context allows. **5.5a is the root dependency** — the others can
proceed in any order after it.

### Phase 5.5a: Voxel change event bus + indexer refactor

**Goal:** Decouple voxel editing from the systems that care about voxel changes.

Current state: `player.gd` directly calls `integrity.register_voxel` and
`integrity.remove_voxel` from inside `_edit_fill` / `_edit_dig`. This works for one
indexer (structural integrity). It will not scale to two (add a building registry), let
alone four or five (biome map, ore depletion tracker, decay system, fire propagation).

Tasks:
- Define a voxel change event: `(grid_id, position, old_material, new_material, cause)`
- Add a signal on the voxel editing layer that fires for every modified voxel
- Refactor `StructuralIntegrity` to be a subscriber rather than a callee
- Establish spatial filtering: indexers declare interest in a region, only get events
  for that region. (HTML-style capture/bubble doesn't fit a flat 3D grid; pub/sub with
  spatial filtering is the right shape.)
- Establish priority + cancellation: structural integrity runs before building registry,
  because a cascade collapse should be batched, not reported voxel-by-voxel
- **Design the bus API for multi-grid from the start** — even if there's only one grid
  for now, the event payload should carry a grid identifier. This costs nothing now and
  prevents a painful refactor when vehicles arrive.

Done when: structural integrity works exactly as it does today, but `player.gd` no longer
imports or references it.

### Phase 5.5b: Construction mode + honest-failure terrain ops

**Goal:** Replace the placeholder fill/dig/flatten verbs with construction-mode equivalents
that respect the design principles, especially "fail honest, not fake a surface."

The v0.0 scaffolding has two problems the player can hit today:
- Additive edits (fill, vertical flatten, default-normal flatten) can place a solid voxel
  where the player is standing, burying them. Currently patched with
  `_push_player_above_terrain`, which is a band-aid.
- Horizontal flatten that can't lower cleanly (because there's material above the cut)
  fakes a floor instead of producing truthful geometry. This violates the thesis.

Tasks:
- Promote "fill / dig / flatten" from placeholder verbs to first-class construction-mode
  operations with explicit semantics:
  - Each operation declares whether it's subtractive-only, additive-only, or both
  - Additive operations explicitly decide what to do when they'd place a voxel at the
    player's position: refuse, displace the player, or treat the displacement as part of
    the operation
  - The insight worth preserving: *subtractive-only editing structurally cannot cause
    fall-through; additive editing always can*
- Horizontal flatten that hits material above the cut should *open a cave* into that
  material, not invent a floor. This is the principle: terrain ops produce truthful
  voxel data, even if that means opening a void.
- Visual + UI affordances for the new construction mode (mode selection, parameter
  configuration, preview rendering)
- Remove `_push_player_above_terrain` once the build-time decision replaces it

Done when: you can't get buried by your own construction, and the design principle
"terrain ops should fail honest" is enforced at the verb level.

### Phase 5.5c (deferred to v0.2): Fracture as mesh extraction

**Moved out of v0.1.** Rationale: the current flood-fill structural integrity with
voxel-aligned collapse is fine for "is this fun?" v0.1 work. The mesh-extraction
fracture is an aesthetics-and-fidelity upgrade, not a gameplay-enabling one. Belongs in
v0.2 ("can I make it pretty?") with the rest of the visual fidelity work.

Forward-looking sketch (preserved here so the design isn't lost):
- When structural integrity decides a region has failed, extract that region from the
  voxel grid as a rigid-body mesh along a *computed failure surface*, not voxel-aligned
  cubes
- Re-integrate into voxels when it comes to rest, or stay as a mesh prop if it doesn't
- This is what unlocks sub-meter fracture precision without sub-meter voxels
- Roughly what Teardown does — their voxels are 10cm, but fractures don't break on voxel
  boundaries; they break along computed failure surfaces and re-voxelize the result
- For determining fracture direction, a localized FEM-style stress tensor calculation
  (in the affected region only, not globally) gives much better results than flood-fill
  support values. See the "FEM" note in Known Hard Problems below.

### Phase 5.5d (deferred to v0.2 or v0.9): Multi-grid foundation

**Moved out of v0.1.** Rationale: nothing in the v0.1 gameplay loop requires multiple
voxel grids. The first vehicle (cart, boat, eventually locomotive) is v0.2 at the
earliest. The *API design implications* of multi-grid stay in 5.5a (the event bus
carries a grid identifier from day one), but actually instantiating a second grid
defers until there's something to put in it.

Forward-looking sketch (preserved here so the design isn't lost):
- Vehicles are independent voxel grids parented to a `RigidBody3D` or equivalent
- Use `VoxelTerrain` (bounded), not `VoxelLodTerrain` (streaming/LOD), for vehicles
- godot_voxel terrains are axis-aligned in their local space; world rotation is handled
  by the scene graph parent. The voxel grid rolls and tilts with the vehicle as a unit.
- Per-grid voxel size is allowed and encouraged: main world at 1m, locomotive at 0.25m,
  boat at 0.5m
- The thesis ("matter is matter") survives because the *physical rules* are the same
  across grids — structural integrity, material properties, fracture mechanics — even
  though grid resolutions differ. The grid is an implementation detail; the physics is
  the abstraction.
- Coupling between grids is mostly via normal physics collision (each grid generates its
  own collision shape). Transfer operations (crash debris from a vehicle integrating into
  the world, or a player extracting a region of the world to make a cart) are bounded
  one-time operations, not continuous coupling.
- Architectural rule of thumb: **the main world is always the default; things become
  separate grids only when they need an independent transform.** A house is part of the
  main world. A locomotive is its own grid because it moves.

### Phase 5.5e (deferred to v0.2 or v0.9): Per-channel non-SDF data

**Moved out of v0.1.** Rationale: temperature, moisture, pressure, momentum, and other
cellular-automata channels are locomotive-era and weather-era concerns. The decision
worth recording now is just that the event bus and any per-voxel data structures should
be designed to *allow* multiple channels at different resolutions — not that they have
to be implemented yet.

Forward-looking sketch:
- godot_voxel's channel system already supports independent per-channel storage,
  compression, and streaming. You're not paying for temperature data in empty sky.
- Different channels can have different spatial resolutions. Temperature at 2m is fine
  because it diffuses slowly. Pressure for steam systems wants 0.25m or smaller. Wind
  vectors at 8m. Each channel is sized for its physics.
- Channels are how non-rendered volume data lives in the world: the tree might be an
  iterated function system for its geometry, but its temperature is tracked in the
  voxel grid at whatever resolution thermal simulation wants.

---

## v0.1 Checkpoint: "Can I Make It Fun/Performant?"

At this point (~11 weeks part-time from start), you have everything from v0.0 plus biomes,
resource gathering with continuous work actions, inventory, crafting, the full material
loop, and the architectural foundation (event bus, construction-mode verbs) needed for
everything after. No enemies or survival pressure yet, but it's a playable sandbox.

**This is the version to show to friends.** Earlier than this, the engine impresses but
there's nothing to *do*; later than this, the polish-vs-feedback ratio starts favoring
public release.

**Performance validation:** Profile on your 5090, then test with aggressive quality
reduction to simulate lower-end hardware. Key metrics: chunk meshing time, frame budget
at various draw distances, structural integrity computation cost, event bus throughput.

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
- **Fracture as mesh extraction (Phase 5.5c)** — sub-voxel fracture surfaces via localized
  FEM, mesh extraction, rigid-body simulation, re-voxelization
- **Multi-grid foundation (Phase 5.5d) — first vehicle prototype**, probably a simple cart
  or rowboat. Not yet the locomotive.
- **Per-channel non-SDF data (Phase 5.5e) — initial channels** for whatever the first
  vehicle and the weather system want (probably temperature and a simple wind vector
  field for atmospheric effects)

### v0.9: "Can I Make It Into A Real Product?"

- **Multiplayer** (Godot 4's multiplayer API + voxel chunk sync)
- Survival loop: health, stamina, hunger, food buffs, comfort system
- Enemy AI and combat (see Pathfinding section below)
- Boss encounters as progression gates
- Procedural dungeons (generated cave complexes — no loading screens)
- Building material tiers (wood → stone → iron-reinforced)
- Death, respawn, bed placement
- Save system (player state + modified chunks + structures)
- Settings menu, keybinding, accessibility
- **Locomotive-class vehicles** — the boiler / firebox / pressure-driven piston
  demonstration. Cellular automata for heat and pressure. This is the "wow, *that's* what
  this engine does" moment that sells the project on its own, and it can only happen once
  multi-grid, fracture, and channel infrastructure are all mature.

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

### Sub-meter precision without the cubic penalty

The naive "shrink voxel size" answer has a real-world cost closer to 3–5x for most
operations, not 8x, because real voxel engines are sparse and surface-dominated (memory
compresses aggressively for fully-solid and fully-air regions; meshing and physics costs
scale with surface area, not volume). But there are better answers than shrinking the
global grid:

1. **Multi-resolution sidecar data.** Render and collide at 1m; track structural integrity
   at 0.5m or 0.25m in a separate sparse dictionary that only exists for modified regions.
   The hard part is the coupling — what happens visually when a sub-region of a render
   voxel fails? See Phase 5.5c (fracture as mesh extraction) for the answer.

2. **Stress and strain as a continuous field, not a per-cell value.** A stress tensor
   sampled at whatever resolution the physics wants, computed via something closer to
   FEM than to cellular automata. Fractures happen along computed surfaces in continuous
   space and produce arbitrary-shape debris. This is Teardown's approach.

3. **Hybrid (voxels for matter, mesh for fracture).** The pragmatic shipping option. The
   voxel grid stays at 1m. Fractures aren't aligned to it because fractures are a
   *transition event* that produces non-voxel outputs (rigid bodies). The illusion of
   sub-meter fracture precision comes from the moment of breaking, not the underlying
   data structure. Recommended for v0.2.

4. **Per-grid voxel size.** Locomotive at 0.25m, boat at 0.5m, main world at 1m. Costs
   nothing in the main world; gives the precision where it matters.

### FEM (Finite Element Method) for fracture direction

FEM is the numerical technique behind real-world structural engineering. Subdivide an
object into many small elements (tetrahedra, hexahedra), approximate the physics as a
system of linear equations relating each element to its neighbors, solve the system, get
a field of stress/strain values across the whole object. It tells you not just "this is
supported" but "this is under 12kN of tension along this axis, exceeding stone's tensile
strength of 8kN/m², so a crack will propagate along this plane."

Relevance to this project: the flood-fill structural integrity is fine for the global
"is this voxel supported?" question. But for determining *fracture direction* during a
collapse event, a tiny localized FEM-ish calculation gives much better results than
voxel-aligned cubes. The plan: keep the flood-fill cheap and continuous, reach for
FEM-style math only when a fracture actually happens, in the affected region only. This
is the foundation under Phase 5.5c.

FEM at game-tick rates over the whole world would be prohibitive. FEM in a small region
during a single collapse event is tractable. The difference is whether it's a continuous
simulation cost or an event-driven one.

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

### Channel architecture

godot_voxel exposes voxel data as a multi-channel volume, not a single typed value per
cell. Relevant channels for this project:

- `CHANNEL_SDF` — signed distance field, float per voxel. Used by TransVoxel for smooth
  terrain. The "how far is this from the surface" mental model maps here.
- `CHANNEL_INDICES` + `CHANNEL_WEIGHTS` — texture blending for terrain (up to 4 materials
  per voxel, weighted)
- `CHANNEL_TYPE` — integer ID, used by the blocky mesher. Not relevant to this project's
  smooth-terrain approach.
- `CHANNEL_COLOR` plus several user channels — available for project-specific data

The voxel grid is a multi-channel spatial database. "What is this voxel?" is not a single
question; it's several independent questions (SDF, material, temperature, moisture, ...)
that share a coordinate space.

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

```
project/
├── addons/
│   └── zylann.voxel/          # godot_voxel module
├── assets/
│   ├── models/                # CC0 models (Kenney, Quaternius)
│   ├── textures/              # terrain materials, UI
│   ├── sounds/                # CC0 audio
│   └── fonts/
├── scenes/
│   ├── world/
│   │   ├── terrain_generator.gd
│   │   ├── biome_manager.gd
│   │   ├── structural_integrity.gd
│   │   └── world.tscn
│   ├── player/
│   │   ├── player.tscn
│   │   ├── player_controller.gd
│   │   ├── work_action_manager.gd  # continuous mining/logging
│   │   ├── inventory.gd
│   │   └── stats.gd
│   ├── building/
│   │   ├── build_system.gd
│   │   ├── snap_manager.gd
│   │   └── pieces/
│   ├── enemies/
│   │   ├── enemy_base.gd
│   │   ├── pathfinding/
│   │   │   ├── raycast_steering.gd
│   │   │   └── nav_grid_3d.gd
│   │   └── types/
│   └── ui/
│       ├── hud.tscn
│       ├── inventory_ui.tscn
│       ├── crafting_ui.tscn
│       └── work_progress_ui.tscn
├── data/
│   ├── items.json
│   ├── recipes.json
│   ├── materials.json         # structural properties per material
│   └── biomes.json
└── scripts/
    ├── voxel_editor.gd
    ├── resource_node.gd
    └── save_manager.gd
```

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
the behavior we want for cave ceilings and unsupported building sections. Their fracture
mechanics — breaking along computed failure surfaces rather than voxel boundaries — are
the model for Phase 5.5c.

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
