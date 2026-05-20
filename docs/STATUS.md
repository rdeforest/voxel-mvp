# Project Status

> **Maintenance contract:** the "Resumption Brief" must reflect the current
> moment. The "Tracker" below it can drift a little. If updating this doc
> after a session takes more than ten minutes, it's too big — shrink it.

---

## Resumption Brief

*Last updated: v0.0 close-out — Phase 5 functionally complete, release plumbing
in place, materials-as-`.tres` refactor landed (commit e00513b), planning
v0.0.1 (persistence-as-replay) while playtesting v0.0.*

**Where you are:** v0.0 is done. The thesis demo works end-to-end: dig a wide
cave, ceiling cells develop a strain gradient that depends on material decay,
the centre of a too-wide span fails into a falling RigidBody3D after the
3-second strain window, and placing a wood beam under the strained ceiling
repairs the gradient outward from the pillar. The structural integrity
algorithm is unified across natural terrain and player-placed parts (same
support propagation, same fall threshold, same strain timer, same flood-fill
into a falling body) — that's the architectural payoff and it's defensible.

Release plumbing in place: top-level `README.md`, `LICENSE` (CC BY-SA 4.0),
build/run instructions, controls reference, license clarity on Godot and
godot_voxel dependencies.

**Pick up here:**

1. **Dink around with the build to validate the v0.0 thesis question.** The
   purpose of v0.0 was always to answer "is this as good of an idea as I
   think it is?" — Robert's call to make. The infrastructure is in place; the
   question is now about *feel*, not implementation.

2. **v0.0.1: persistence as replayable history.** Save/load is now scoped as
   v0.0.1 with a sharper framing than "add a save system." The save file is
   the journal of actions that produced the world — snapshot plus action
   tail — which doubles as a bug-reproduction artifact, a step-debugging
   tool, and a regression-test harness. The Action pattern already makes
   this feasible; the work is serialisation, snapshot cadence, schema
   versioning, and determinism discipline. See `roadmap.md` for the full
   design.

3. **Playtester binaries.** Linux + macOS + Windows binaries via GitHub
   Actions (cross-compile from a Linux runner with MinGW for Windows, native
   on macos-latest). Not yet started. Robert wants to play with v0.0
   locally first to decide it's not embarrassing before distributing.

4. **v0.1 scoping.** When the v0.0 (and v0.0.1) answers come back "yes," the
   v0.1 question is "can I make it fun/performant?" — see `roadmap.md`
   Phases 1, 3, 4, the deferred list below, and the new "honest physics
   interaction" design direction (SDF seam + load propagation + falling
   damage + fallen-dirt-as-terrain, unified under the principle that
   transient physics state and persistent terrain state should be able to
   become each other).

**Architectural status — what's solid, what's known-imperfect:**

- Structural integrity is the load-bearing thesis claim. It works. The
  lazy-expansion model handles both fresh digs and post-collapse exposure;
  per-column bedrock detection distinguishes real bedrock from suspended
  mass; lazy registration is bounded by material decay so the cascade
  terminates naturally.
- Parts are parametric (one-line `.tres` files for new shapes), multi-axis
  rotation works (Vector3i state, computed Basis applied to a shifted
  instance), material is independently selectable at build time.
- Physics integration handles the cases we hit: thin parts use `continuous_cd`
  to avoid tunnelling, fills refuse on top of RigidBody3Ds, terrain edits
  wake sleeping bodies.
- **Performance is CPU-bound** and observably degrades under heavy digging.
  Threading is the right next move if it bites; GPU offload is a known-hard
  problem documented in the roadmap. Budget-consumption telemetry deferred
  to v0.1.
- SDF seam matching (Option A2) is **deferred to v0.1+**. The realisation
  during scoping: our parts are sub-cell (0.012–0.15m thin axes, 1m cells),
  so writing SDF samples per cell can't represent the parts at the right
  resolution. The v0.0 thesis stands without it; v0.1+ revisits this under
  the "honest physics interaction" design direction — where a buried beam
  either breaks under load or pushes the dirt aside depending on relative
  material strength, pairing naturally with load propagation and falling
  damage.

---

## Tracker

### v0.0 — Phase status

| Phase | State | Notes |
|-------|-------|-------|
| 0 — Foundation | Complete | godot + godot_voxel build chain, walking-around prototype |
| 2 — Terrain Modification | Complete | dig, fill, flatten with refuse-don't-deform |
| 5 — Building System | Functionally complete for v0.0 | Parts, structural integrity, cave integrity, pillar reinforcement all working; SDF seam matching deferred to v0.1+ |

### v0.0.1 — Scope

Full design in `roadmap.md`. Summary: serialise `Action` history as an
append-only journal, periodic state snapshots, versioned save format with
action-schema versioning, deterministic replay (seeded RNG, no wall-clock
reads), debug controls for stepping through history. Not started.

### In flight

*(nothing in flight — playtesting v0.0 to answer the thesis question)*

### Bugs

| ID | State | Notes |
|----|-------|-------|
| 2c | Closed | Player fall-through fixed via `Action.validate()` refusal |
| 2a | Deferred | Flatten clears only one sheet above — cosmetic; deferred until building system replaces flatten |

### Architectural commitments worth not re-litigating

- **Track Godot 4.6-stable + godot_voxel v1.6.** Pinned in `tools/versions.env`.
- **Double-precision godot_voxel build from day one.** Non-retrofittable.
- **No engine forks.** Pull upstream directly.
- **`godot/modules/voxel` symlink, not `custom_modules`.**
- **Worklist-fixpoint propagation for terrain support.** Not generalised
  until a second customer (fatigue/fluid/temperature) appears.
- **Per-column bedrock detection (`_lowest_registered_y`).** Distinguishes
  real bedrock from suspended mass without per-cell `column_below_me_is_clear`
  bookkeeping.
- **Lazy expansion bounded by material decay.** Cascade stops where support
  reaches `FALL_THRESHOLD`; for STONE that's ~20 cells per chain.
- **Part support recomputed fresh per frame, sorted bottom-up by `placement_y`.**
- **Per-cell *stack* of parts (`Array[Node3D]`).** Disambiguated by `placement_y`.
- **In-limbo semantics.** Parts with dirty dependencies don't accumulate
  strain — avoids transient zeros triggering 3-second countdowns that would
  resolve before expiry.
- **Action-as-data; targeting at the call site.** Actions take final
  computed parameters, not raw input.
- **Refuse-don't-deform extended to physics state.** FillAction refuses on
  top of RigidBody3D via `intersect_shape`.
- **FIFO dirty queue.** BFS is the right shape for support propagation; the
  shift cost on typical queue sizes isn't where the time goes.

### Done this v0.0 cycle (chronological-ish)

- Action infrastructure (`scripts/actions/`), refuse-don't-deform principle.
- Part/Schematic resource hierarchy, parametric dimensions, procedural build.
- Part-level structural integrity (separate from terrain `voxel_data`),
  per-cell stack semantics, direct-supporter selection, material decay
  propagation.
- Multi-axis 90° rotation with Vector3i state, AABB-driven instance shift.
- Strain visualisation: emission tracking support color, hover tint,
  in-limbo pause.
- Falling-part physics: `continuous_cd`, sleep-wake on terrain change,
  fill-refuses-on-RigidBody3D.
- Cave integrity: dig-time registration of exposed cells.
- Lazy-expansion model with per-column bedrock detection — fixes
  "digging strained reveals blue" and "collapse leaves untracked cells"
  in one architectural pass.
- Register-part dirties terrain neighbours so pillars actually support
  ceilings.
- Material override at construction time (M key cycles wood / stone /
  metal / dirt / sand).
- Debug-cube toggle wired to V key.
- README + LICENSE + dependency-licensing notes.
- Materials → `.tres` refactor: `Materials` is now a `Resource` subclass
  with `@export` fields; six singletons load from `assets/materials/*.tres`;
  `from_name()` lookup lazily built. Mirrors the Parts pattern.

### Deferred to v0.1+ (the "can I make it fun?" question)

| Item | Why deferred |
|------|--------------|
| SDF seam matching (Option A2) | Sub-cell parts can't be represented at 1m voxel resolution; better answered by physics-driven part-vs-terrain interaction (load propagation + falling damage + material relative strength) |
| Load propagation (top-down weight pass) | Pairs with falling damage and SDF-seam-as-physics; not needed for v0.0 thesis |
| Falling damage (impact breaks parts, crumbles dirt) | Needs a damage model; v0.1 polish |
| Hinge-at-boundary collapse | Polish on falling drama |
| Fallen-dirt-as-terrain | RigidBody3D rejoining SDF when at rest — needs settle detection + SDF write path |
| Sub-assemblies + planning mode (Dwarf-Fortress queue) | Significant UI work; not a thesis question |
| Free-form placement with physics settle-to-construction | Architectural change; current grid-aligned demo carries thesis |
| Snap point authoring UI | Data structure exists; UI is v0.1 |
| Specialised joinery pieces (doors, stairs, mating constraints) | Rectangular parts demonstrate the system |
| Terrain strain on mesh surface (replace debug cubes) | Real shader work |
| Highlight parts depending on about-to-fall things | Dependency-graph walk; nice-to-have |
| Budget-consumption telemetry | Dynamic budget adjustment depends on this |
| Player-controlled dig/fill shapes & sizes | UX polish |
| KSP-style parametric Part dimensions in-game | Tooling polish |
| Per-material strain duration; nature-of-change reset scaling | Tuning pass |
| Gap-between-layered-parts | Needs `PartData.dimensions`; punted |
| Mid-break Part destruction | Whole-part destruction is enough for v0.0 |
| Non-adjacent linkages (ropes, cables) | New data structure required |
| Material fatigue (cumulative strain history) | Only meaningful with mobs (v0.9) |
| In-game Schematic editor | Hand-authored `.tres` is fine; v0.9+ |
| Workbench radius | Valheim survival-loop mechanic; v0.9+ if at all |
| Cross-platform binary builds (Windows via MinGW from Linux, macOS native, Linux native) | Release plumbing; GitHub Actions pattern |

### Known limits (recorded, not fixed)

- **Flatten preview Z-fights with the surface it's matching.** The preview
  plane is positioned at the hit point, which is exactly where the surface
  is, so the GPU can't decide which to draw in front. Cosmetic; cleanest
  fix is a small forward offset on the preview plane normal.
- **`_resume_unfinished_floods` budget starvation:** components larger than
  `DETECTION_BUDGET` (500 voxels) take multiple settled frames to fully detect.
- **`PLAYER_CLEARANCE = 1.0m`** in Fill/Flatten is a guess; tune if needed.
- **Lazy-expansion cascade per dig is bounded by material decay budget.** For
  STONE (decay 0.05), the cascade reaches ~20 cells before support hits zero
  and lazy registration stops. Fine for support computation (the chain is
  already zero there) but the future load-propagation pass will need its own
  cascade rules.
- **`_recompute_column_low` scans `voxel_data`.** When removing the lowest
  cell in a column, we re-scan the entire `voxel_data` dictionary. Fast for
  ~10k tracked cells; replace with per-column ordered set if tracked count
  grows large.

---

## How to update this doc

After each session:

1. Rewrite the **Resumption Brief** completely. It must reflect *right now*,
   not history. If you find yourself adding to it instead of replacing, the
   item probably belongs in the Tracker.
2. Move "in progress" items in the Tracker to "Done this v0.0 cycle" as they
   finish. Add new entries to Deferred / Known Limits as they emerge.
3. If the Tracker is hard to navigate, it's too big. Move older "Done"
   entries into a one-line summary like "Phase X complete (commit abc123)"
   and trust git for the detail.
4. If updating this doc took more than ten minutes, something is wrong with
   its shape.
