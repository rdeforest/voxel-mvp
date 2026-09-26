# Scenario Languages: Captures, Assemblies, Methods

*Drafted by Claude, 2026-09-26, from a design chat with Robert. **Draft for review:** nothing here
is built. Prior art and sources are in
[`../reference/08-scenario-languages-research/`](../reference/08-scenario-languages-research/00_INDEX.md).
The manifesto wins if this disagrees with it.*

## Why

Our player-facing actions have been doing double duty as test instruments, and both roles
suffered. FillVoxel, EmptyVoxel, CSG re-stamping and Dig at 30 m exist because development needs
exact control. Judged as game verbs, they produced a run of "needs a call" questions (single-voxel
cubes, material-only re-stamps, digging under yourself) that are really questions about test tools.

In the real game the player states intent ("make this space empty", "stack wood here", "build a
cabin"), the avatar works out the steps, and the grid is invisible: a board placed 10° off north
should look like one placed at 0°. Testing needs the opposite: exact, grid-aware control, and
exact reproduction.

So we split the two and give both a common language for describing what exists and how it came to be.

## Decisions (Robert, 2026-09-26)

- **Build our own.** Fit to our problem beats best-fit borrowing; the research found no format that
  covers what we need anyway.
- **JSON is the canonical form.** Godot has a built-in JSON parser and no YAML (verified in the
  engine source: `core/io/json.*`, and no YAML in core or modules), so JSON avoids a dependency.
  **CoffeeScript is the human authoring surface:** tools that emit *parameterized* JSON, never an
  expanded list, so the game can still re-parameterize (drag a wall's endpoint, re-evaluate).
- **Expressions and evaluation run in C++.** Complex builds will make evaluation a hot path.
- **Three kinds of description, three formats.** A *field capture* is the bitmap, an *assembly* is
  the vector drawing, and a *method* is the sequence of commands that produce a drawing.

## The shared core

Assemblies and methods share **one expression language and one registry of generators and
predicates.** The battlement repeat in an assembly and the "place each merlon" step in a method
call the same `wall_segments`. This is the design's central commitment.

- **Values:** number, length (m), angle, point, frame, material, part type, enum, bool, cell.
  Internally everything is metric; an imperial display is only a UI option (FEAT040).
- **Expressions:** a closed, non-Turing-complete language. Parameter references, arithmetic,
  comparison, a conditional, `min/max/floor/ceil/round/clamp`, and vector helpers (`distance`, `lerp`).
  No user-defined functions, no loops, no recursion. In JSON they're strings
  (`"(platform - thickness) / 2"`), parsed once in C++ into a cached syntax tree. Not Godot's
  `Expression` class, which can call methods (its sandbox wasn't checked).
- **Generators** are named, deterministic C++ functions that yield *frames* (the location-generator
  idea from build123d): `repeat`/`split` along an axis with CGA-style absolute, relative and
  floating sizes, and **explicit fit modes** (`stretch`, `center`, `clip`, `exact`). CGA's default
  of silently clipping the last element would leave half-merlons.
- **Predicates** are named world queries for method preconditions (`area_clear(box)`,
  `solid_at(cell)`), implemented in the engine, never written inline.
- **Determinism:** evaluated transforms are canonicalised to a snap epsilon, so repeats stay
  symmetric (the float-drift problem Besiege players report).
- **One evaluator, two hosts (to investigate).** CoffeeScript tools also need to evaluate
  expressions (for previews and linting). Rather than writing the grammar twice and keeping a
  shared conformance corpus, build the C++ evaluator as a Node-API addon, or compile it to
  WebAssembly, so the tooling calls the engine's own code. Robert notes that Node's C/C++
  integration keeps maturing. Unverified; decide when the evaluator exists.

## Format 1: field captures (the bitmap)

"Snapshot" is already taken (`WorldSnapshot`, the F5 save), so these are **field captures**.

- **What:** the output of `fill_region` and `fill_indices_region` over a region. That's the SDF as
  float32 and the material as uint8 at the same lattice points, stored with metadata (origin, cell
  size, dim, generator parameters, sampling convention). The file is an `.npz`, which numpy and
  Blender scripts can read and GDScript can write through `ZIPPacker`.
- **Why:** bit-exact and independent of the generator. GUT compares captures with `==` on packed
  arrays.
- **The EditStore blob stays the *tree* fixture.** It's exact, but only relative to a bit-identical
  `TerrainField`, so it should carry a generator fingerprint (a few recorded samples). A change to the
  generator then refuses the fixture instead of silently changing what it means.
- **Blender:** `tools/capture_to_vdb.py`, run inside a blender.org Blender, writes a float SDF grid
  and an int material grid (never as a level set, since our SDF isn't a true distance; half-float
  off). Python is the right choice here because the script runs inside Blender. Robert's Devuan
  Blender 4.3.2 lacks the `openvdb` module, so a blender.org build is needed. **OpenVDB is not
  linked into the engine**, and VDB is never a fixture: our octree can't be stored in a VDB grid
  without loss.
- **Meshes:** export the DC mesh as glTF through Godot's built-in `GLTFDocument` for "what did the
  mesher actually draw."

## Format 2: assemblies (the vector drawing)

An assembly is part types, parameters and composition. Evaluating it yields a flat placement list,
and imprinting that list is how it enters the world.

- **Parameters** with type, units and default (which may be an expression). **Derived values** are
  resolved in dependency order, with an error on cycles.
- **Parts:** a registry id (a CSG box, cylinder or sphere under the hood), size, placement frame,
  and material. Material is inherited from the parent unless set (LDraw's "colour 16").
- **Repeats** come from generators (see above); `when:` includes or omits an element.
- **Sub-assemblies:** `use:` + `with:` (parameter bindings), attached **by named anchors**
  (`door.hinge`, `wall.end`), not by magic coordinates. This is KSP's attach nodes, Minecraft's jigsaw.
- **Overrides** are a sparse layer keyed by evaluated path (`"merlon[7]": {omit: true}`), borrowed
  from USD's `over`. That's how a player's edits and battle damage are recorded against a
  parametric original.
- **Rotation** is a quaternion or axis-angle, never an enum and never a part-type variant (no
  "beam_north"). Minecraft's rotated-schematic bugs come from getting this wrong.
- **Versioning from day one:** `format:` plus a part registry with aliases for renamed parts.
- **Output:** a flat list of `(path, part, material, transform, size)` per part. Imprint consumes it,
  and **PartIndex can key parts by path.** That may be the answer to
  [`part-index-sub-cell-parts-untracked`](../../bugs/part-index-sub-cell-parts-untracked.md): identity
  by path, not by cells.
- **Doc 17's concept library is this format on the play side.** A named build *is* an assembly, and
  sharing a library entry means exporting its JSON
  ([`17-consider-and-hypothetical-mode.md`](17-consider-and-hypothetical-mode.md)).

Sketch (the JSON is canonical; the CoffeeScript is the authoring side and emits it):

```coffee
assembly 'curtain_wall',
  params:
    A: point(), B: point()
    thickness: m 2, height: m 7, material: 'cemented_stone'
    battlements: side: enum('outer', 'inner', 'none'), low: m(1), high: m(2), gap: m(0.5), merlon_w: m(1.5)
  frame: from: '$A', to: '$B'
  parts: [
    part 'core', 'stone_block', size: ['L', 'height', 'thickness']
    repeat 'merlon', axis: 'x', over: [0, 'L'], fit: 'stretch_gaps', end_with: 'emit',
      pattern: [{size: 'battlements.merlon_w', emit: yes}, {size: 'battlements.gap'}]
      part: 'stone_block', size: ['cell.size', 'battlements.high - battlements.low', 0.5]
  ]
```

## Format 3: methods (the commands)

Methods follow HTN, the approach Guerrilla's Decima planner and *Transformers: Fall of Cybertron*
shipped with. We take HDDL's *structure* (tasks, methods, ordering, typed parameters) and none of its
Lisp syntax.

- **Tasks** decompose through **methods** into primitive **steps**. A step is one of our Actions
  with its resolved constructor arguments (`dig`, `csg`, `build`, ...), plus test-only steps:
  `player_at`, `advance(frames)`, `settle`, `mark(note)`.
- **Goals** (state predicates such as `area_clear`) can be mixed with tasks, as in GTPyhop. A goal is
  checked after its steps run; **in a test, that check is the assertion.**
- **Ordering:** authoring allows `unordered` blocks ("four walls in any order, then the roof").
  The runtime planner linearizes them (top-down, strictly ordered, the way every shipped game
  planner found works), and a recording that built the walls in any order still validates against
  the method.
- **Repetition:** parameters come from generators (`each seg in wall_segments(...)`), or from
  recursion when the count depends on world state ("keep clearing until `area_clear`").
- **Recordings store bound values**, so replays are exact. The same generator can be re-run to
  check that it still produces those bindings, which is a separate regression gate.
- **Three uses of one format:**
  1. Hand-written test scenarios.
  2. Recordings of play.
  3. Later, the planner's output when the play layer's directives turn a player's goal into steps
     the avatar carries out over time ([doc 08](08-continuous-work-actions.md)'s work-action state
     machine). In tests, steps execute instantly.

  The step record is shaped so it could also be the successor game's op-log unit
  ([doc 05](05-network-architecture.md)). That's not a requirement here.
- **JSON numbers:** `JSON.stringify` defaults to about 14 significant digits, which is lossy for
  doubles, and it writes -0.0 as "0.0". Recordings must use `full_precision = true`, and a round-trip
  test must pass before we rely on it (a position a fraction of a unit off can flip a lattice decision).

## The record → test loop

1. **Hook:** every gameplay action runs `validate()` and `execute()` in one place, `player.gd`.
   Record there, not at construction: `voxel_preview_renderer.gd` constructs an action every frame.
   Each step records its resolved arguments, the player's position (the safety checks read it),
   the physics frame, and the result of `validate()`.
   - Copy CSG's live shape object by value.
   - Record a construction part's path and dimensions.
   - Record the `mpmthaw` console command as a step too.
2. **`rec start`** requires the world to be settled (the same gate as F5) and captures the starting
   blob. **`rec fresh`** starts from the generator alone, which reproduces most reliably.
3. **`mark [note]`** saves the camera, FOV, dcworld settings, the aimed cell with its probe report,
   and a screenshot. That turns "this looks wrong" into something an assertion can be written from.
4. **Replay runner** (GUT, headless, no World scene): the simulations tick explicitly at 1/60 s,
   never on wall-clock time, and replay **stops at the first step whose result differs from the
   recording**, the lesson from Riot's determinism work. This needs two small seams: tick functions
   on DetachmentScout and StructuralIntegrity.
5. **Trim** by deleting steps; once an assertion exists, an automatic delta-debugging (ddmin)
   pass can shrink it. A new scenario test starts `pending` and must fail on the buggy code before
   the fix goes in. Recordings are never used as approval snapshots, because that would lock in
   the bug.

**Gaps to close first:**
- Saves don't keep PartIndex.
- DetachmentScout's pending work is missing from `is_quiescent()`.
- MPM orders its freeze by camera distance, which makes structural event order depend on the camera.
- A fresh `mesh_world` doesn't exercise the live incremental mesher, so render bugs in that path
  need a camera-path replay.

## The instrument layer (test tools)

These are grid-aware and deliberately non-diegetic. They replace FillVoxel, EmptyVoxel and the rest
as instruments.

- **Inspect:** the probe also reports the owning leaf, its size and field state, all 8 corner values,
  and the mesher's sign test, with an optional overlay of leaf boundaries and corner signs.
- **Set exactly:** console writes through the normal EditStore path, so the edit is first-class: it
  renders and emits events like any edit. Examples: set a cell's 8 corners, set a cell's material,
  and stamp a typed CSG shape by numbers instead of by aim.
- **Named saves** (`save <name>` / `load <name>`) and assembly import/export commands.

## Build order

Each phase is gated by GUT and ships on its own.

1. **Instrument layer + step language + recorder + replay runner** (GDScript). This pays off at once
   in tests.
2. **Field captures + the Blender script + glTF mesh export.**
3. **C++ expression evaluator + assembly v0** (parts, `use:`, anchors; a cabin can be exported,
   imported and stamped into a new world), then parameters, repeats and overrides.
4. **HTN planner + directives** (the play layer). This belongs with the directives work; the
   parts above don't wait for it.

## Dependencies this introduces

| Dependency | Why | When |
|---|---|---|
| Node (latest) | runs the CoffeeScript authoring tools | phase 1 or 3, with the first tool |
| CoffeeScript 2.7 | authoring surface (the project's preferred tooling language) | as above |
| Blender from blender.org (optional) | bundles the `openvdb` Python module that `capture_to_vdb.py` needs | phase 2, for viewing captures only |

The project has no dependency list yet. The first of these to land should create one, recording
each dependency and why it exists.

## Open questions

- **Battlement wording:** does "crenels 1 m at the lows and 2 m at the highs, 0.5 m gaps" mean parapet
  1 m and merlons 2 m tall, with 0.5 m crenels? And does the 3 m platform overhang the 2 m wall
  equally on both sides?
- **Imprint order** for unions versus cuts (a gate carved through a wall) is part of the format's
  meaning and must be specified: unions, then cuts, then children?
- **Units in JSON:** plain numbers in metres and degrees, with units only in the CoffeeScript surface?
- **Do instrument writes bypass player safety?** I'd say yes, since a test tool should be able to do
  anything; they still emit true events.
- **Hand-written tests:** a GDScript builder that reads and writes the same JSON, or JSON files only?
  I'd do both, with JSON as the source of truth.
- **Where the CoffeeScript tools live** (`tools/`, with a `package.json` at the root?), and how
  they're run from `tools/build`-style scripts.
