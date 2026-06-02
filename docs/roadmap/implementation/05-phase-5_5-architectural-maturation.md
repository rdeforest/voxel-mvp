# Phase 5.5: Architectural Maturation

**Goal:** Replace v0.0's direct couplings with the architecture needed
for the rest of v0.1.
**Version target:** 0.1

This phase contains the items deferred from Phase 5 plus the
architectural insights from the v0.0 retrospective. Deliberately split
into independent sub-phases so each can be tackled when context allows.
**5.5a is the root dependency** — the others can proceed in any order
after it.

A vision-drift hazard to name: this phase is *structural*. There's no
new feature for a player to do at the end of most of these sub-phases.
The temptation to skip them in favor of "real gameplay" is real, and
is wrong. The architecture decisions made here govern what v0.2 and
v0.9 can be.

## 5.5a — Voxel change event bus + indexer refactor

**Status: DONE (commit ee80b63).** Full spec at
[`../design/04-event-bus.md`](../design/04-event-bus.md).

Decouple voxel editing from the systems that care about voxel changes.
Actions emit events; structural components subscribe. The bus is multi-
grid-shaped from day one (every event payload carries a `grid_id`)
even though only one grid exists.

## 5.5b — Construction mode + honest-failure terrain ops

**Status: DONE (commits 15308bd, d2b7bbd).**

Replace the placeholder fill/dig/flatten verbs with construction-mode
equivalents that respect design principle #7: terrain ops should fail
honest, not fake a surface.

Shipped in three sub-phases:

- **5.5b1** — `AdditiveAction` base class declaring the verbs that can
  bury the player (Fill/Flatten/Construction); `PLAYER_CLEARANCE`
  lifted into the base.
- **5.5b2** — `FlattenAction` rewritten with column-based work
  computation: cells in the cut box are bucketed by lateral projection
  onto the plane; each column cuts only if it reaches existing air
  within radius, and fills only if it reaches existing solid. Symmetric
  box around `plane_point`. Per-work-cell endanger check catches both
  "fill into player capsule" and "remove player's support cell."
- **5.5b3** — `Action.preview()` + `VoxelPreviewRenderer`. Cells
  highlighted by intent (air = red, solid = blue, part = yellow);
  refusal lerps colors toward grey. Two-pass visible/obscured
  rendering. Idealised sphere/plane previews dropped from Dig/Fill/
  Flatten.

Also landed alongside: Raise/Lower/FillVoxel/EmptyVoxel verbs (commit
3ebf5cf), and the tools/activities UI overhaul that organises the nine
verbs under three top-level tools (None / Landscape / Construction)
with Tab cycling tools and 1-9 selecting activities.

The principle that survived: *subtractive-only editing structurally
cannot cause fall-through; additive editing always can.* Encoded in the
type hierarchy.

## 5.5c — Fracture as mesh extraction

**Status: pending (v0.1).** Moved back into v0.1 from v0.2.

**Rationale:** testing "is this fun?" requires destruction that *feels*
honest, not just structurally accurate. Voxel-aligned cubes flying off
in a collapse read as a programmer-art prototype; mesh-extraction-
along-a-computed-failure-surface reads as a real world. This is
upgrade-as-gameplay, not upgrade-as-polish.

- **FEAT025**: Mesh-extraction-along-computed-failure-surface — when
  structural integrity decides a region has failed, extract that region
  from the voxel grid as a rigid-body mesh along a *computed failure
  surface*, not voxel-aligned cubes. Re-integrate into voxels when it
  comes to rest, or stay as a mesh prop if it doesn't. This is what
  unlocks sub-meter fracture precision without sub-meter voxels —
  Teardown's trick.
- **FEAT026**: Localised FEM-style stress tensor — for determining
  fracture direction (in the affected region only, not globally). See
  the FEM note in
  [`../design/07-known-hard-problems.md`](../design/07-known-hard-problems.md).
  This is what enables material-specific break locations (5.5f).

## 5.5d — Multi-grid foundation

**Status: deferred to v0.2.**

Nothing in the v0.1 gameplay loop requires multiple voxel grids. The
first vehicle (cart, boat, eventually locomotive) is v0.2 at the
earliest. The *API design implications* of multi-grid stay in 5.5a (the
event bus carries a grid identifier from day one), but actually
instantiating a second grid defers until there's something to put in
it.

Forward-looking sketch (preserved here so the design isn't lost):

- Vehicles are independent voxel grids parented to a `RigidBody3D` or
  equivalent.
- Use `VoxelTerrain` (bounded), not `VoxelLodTerrain` (streaming/LOD),
  for vehicles.
- godot_voxel terrains are axis-aligned in their local space; world
  rotation is handled by the scene graph parent. The voxel grid rolls
  and tilts with the vehicle as a unit.
- Per-grid voxel size is allowed and encouraged: main world at 1m,
  locomotive at 0.25m, boat at 0.5m.
- The thesis ("matter is matter") survives because the *physical rules*
  are the same across grids — structural integrity, material
  properties, fracture mechanics — even though grid resolutions differ.
  The grid is an implementation detail; the physics is the abstraction.
- Coupling between grids is mostly via normal physics collision (each
  grid generates its own collision shape). Transfer operations (crash
  debris from a vehicle integrating into the world, or a player
  extracting a region of the world to make a cart) are bounded one-
  time operations, not continuous coupling.
- **Architectural rule of thumb:** the main world is always the
  default; things become separate grids only when they need an
  independent transform. A house is part of the main world. A
  locomotive is its own grid because it moves.

## 5.5e — Per-channel non-SDF data

**Status: deferred to v0.2.**

Temperature, moisture, pressure, momentum, and other cellular-automata
channels are locomotive-era and weather-era concerns. The decision
worth recording now is just that the event bus and any per-voxel data
structures should be designed to *allow* multiple channels at different
resolutions — not that they have to be implemented yet.

Full spec at [`../design/06-channel-architecture.md`](../design/06-channel-architecture.md).

## 5.5f — Honest destruction

**Status: pending (v0.1).**

Destruction has to *feel* right for the fun question to land. 5.5c
gives the visual primitive (mesh-extraction fracture); this sub-phase
makes the *where it breaks* answer material-aware, and adds the impact
and slumping behaviour that makes a collapse read as a real event
instead of a numeric threshold being crossed.

- **FEAT027**: Material-specific break locations:
  - Stone breaks where strain is greatest (uses FEAT026's stress
    tensor).
  - Dirt breaks where insufficiently supported (current threshold-based
    behaviour; keep).
  - Wood breaks at the bend / attachment point (cantilever stress).
- **FEAT028**: Falling damage — impacts crumble dirt further, splinter
  wood, chip stone. Pairs with FEAT025 (the broken pieces are mesh
  extractions, not cubes).
- **FEAT029**: Hinge-at-boundary collapse — material with one strong
  attachment slumps rather than flies off. Stops the "spinning beam"
  gyroscope class of physics weirdness.

## 5.5g — Construction reaching real usefulness

**Status: pending (v0.1).**

Construction is *tantalizingly close* to useful today. This sub-phase
finishes the job: parts attach to each other properly, snap behaviour
exists for those who want it, and you can author assemblies bigger
than one part at a time.

- **FEAT030**: Welding / joining — intersecting parts (cross beams)
  mutually support. Closes the known "vertical beam on cantilever
  isn't supported" limit.
- **FEAT031**: Snap-modifier hotkeys — opt-in grid alignment on top of
  the free placement we already have.
- **FEAT032**: Rotation snap — finer-than-90° rotations with a snap
  modifier.
- **FEAT033**: In-game parametric part resize (KSP-style) — drag
  handles or chord keys to change a part's dimensions.
- **FEAT034**: Pick-and-stamp plane orientation — click an example
  wall to capture its plane; reuse for vertical flatten elsewhere;
  supports "make a ramp, keep that plane for the next clicks."
- **FEAT035**: Sub-assemblies + planning mode (DF-queue) — define a
  multi-part assembly, then place or queue many copies. (Initial scope:
  hotbar + queue. Full DF-style planning overlay deferred to v0.9.)

## 5.5h — Quality of life, performance, bugs

**Status: pending (v0.1).**

- **FEAT036**: Slow-step movement / stop-at-edge toggle — don't run off
  your construction.
- **FEAT037**: First-person hands — visible at edit time; per-tool
  animation. (Avatar art; pairs with the HUD-icon pass.)
- **FEAT038**: HUD icons — replace text labels for tools/activities/
  parts/materials. (Art-dependent; see `../../art-wishlist.md`.)
- **FEAT039**: Crosshair — mode-aware reticle. (Art.)
- **FEAT040**: Imperial units display option — user preference.
- **FEAT041**: Stress-overlay on SDF surface — color the Transvoxel
  surface via terrain shader instead of floating wireframes. Subsumes
  the "MultiMesh debug viz" item.
- **FEAT042**: Per-material strain duration / nature-of-change reset
  scaling — tuning pass.
- **FEAT043**: Budget-consumption telemetry — gather frame-time-by-
  system so the perf budget table becomes verifiable.
- **FEAT044**: Perf baseline instrumentation — `Time.get_ticks_usec`
  deltas on action.execute. Cheap regression detector.
- **FEAT045**: Replay harness + collapse-detector state machine —
  deterministic replay against a saved snapshot; natural home for
  catching collapse-detector edge cases.

Bugs to close in v0.1:

- **FEAT046**: Vertical-on-horizontal beam support — coordinate-snap
  edge in `_direct_part_supporter`. Surfaces when welding (FEAT030)
  lands.
- **FEAT047**: Spinning-beam physics quirk — investigate the gyroscope
  behaviour observed during playtest.

## v0.1 checkpoint

At the end of v0.1: everything from v0.0 plus biomes, resource
gathering with continuous work actions, inventory + crafting + material
tiers, honest mesh-extraction fracture with material-specific break
locations, construction that's actually *useful* (welding, snap
modifiers, in-game part resize, pick-and-stamp), and the QoL pass
(slow-step, first-person hands, HUD icons, perf telemetry). No enemies
or survival pressure yet, but it's a playable sandbox where the
destruction feels honest, the construction feels solid, and there's a
gameplay loop to test.

**This is the version to show to friends** (briefly — then drop a v0.5
playtester build with binaries). Earlier than this, the engine
impresses but there's nothing to *do*; later than this, the polish-vs-
feedback ratio starts favoring public release.

**Performance validation:** Profile on the 5090, then test with
aggressive quality reduction to simulate lower-end hardware. Key
metrics: chunk meshing time, frame budget at various draw distances,
structural integrity computation cost, event bus throughput.
