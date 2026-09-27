# Scenario Languages: Captures and Methods

*Drafted by Claude, 2026-09-26, from design chats with Robert. **Accepted 2026-09-26**; the open
questions at the end remain. Phase 1 is scheduled for the 2026-09-27 overnight session. Prior art and sources are in
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

So we split the two, and give both a common language for describing what exists and how it came to be.

## Decisions (Robert, 2026-09-26)

- **Build our own.** Fit to our problem beats best-fit borrowing; the research found no format that
  covers what we need anyway. This territory has been explored before, but rarely, and each explorer
  had different goals, so the reasoning gets written down as we go.
- **JSON is the canonical form.** Godot has a built-in JSON parser and no YAML (verified in the
  engine source: `core/io/json.*`, and no YAML in core or modules). **CoffeeScript is the human
  authoring surface:** tools emit *parameterized* JSON, never an expanded list, so the game can
  still re-parameterize.
- **Expressions and evaluation run in C++.** Complex builds will make evaluation a hot path.
- **Two formats.** A *field capture* is the bitmap. A *method* is the commands that produce a result.
  **An assembly is a method plus a product description**: the ordered, parameterized steps that
  build a thing, together with what the finished thing is.
- **Construction order comes from the builder, not from a format rule.** How the prototype was
  built decides which operations happen and in what order, and how far each one reaches (see
  Assemblies).
- **Units are preserved as written** (see The shared core).
- **Instrument writes bypass player safety.** When such a write would bury the player or remove
  the ground under them, the player is switched to fly mode. The same safety check decides when.
- **Tests:** a GDScript builder API *and* JSON files, with JSON as the source of truth.
- **Tools** live in `tools/`, with `tools/package.json`. Scripts are executable and start with
  `#!/usr/bin/env coffee`.

## The shared core

Methods, assemblies and generators share **one expression language and one registry of generators
and predicates.** A battlement repeat in an assembly and a "place each merlon" step call the same
generator. This is the design's central commitment.

- **Values:** number, length, angle, point, frame, material, part type, enum, bool, cell.
- **Units are kept as authored.** A quantity is a string, `"#{number} #{unit}"`, with the number
  kept as the decimal text the author typed (never passed through a binary float) and only the
  unit's spelling canonicalized: `"5.5 foot"`, `"9.8 meter / second ** 2"`. No normalization to a
  base unit; 66 inches stays 66 inches. The parser also accepts `"2 ft"`, `"2'"`, `[2, "feet"]` and
  `[2, "ft"]`. Mixed-unit forms like `5'6"` or `5 ft 6 in` are written as a sum in the expression
  language, `"5 foot + 6 inch"`, so there's no special case. Values convert to metric only at
  evaluation and are never written back converted. We use Pint's definitions file, not its parser;
  our grammar decides what parses. That keeps `2 ft` exact: 0.3048 m has no exact
  binary representation, so converting and saving would lose the value. It also keeps intent, such
  as a deliberately imperial house beside a metric one. Dimension checking makes "metres + degrees"
  an error. `'` means feet for a length and arcminutes for an angle; the parser resolves it from the
  parameter's declared type, and it's an error where the type is unknown. Plain numbers are allowed
  only for dimensionless values.
- **The unit table uses Pint's definition format** ([`default_en.txt`](https://github.com/hgrecco/pint/blob/master/pint/default_en.txt),
  BSD-3-Clause), vendored with its notice kept, and pinned by the document's format version. That's
  one line per unit: `foot = yard / 3 = ft = feet`, `furlong = 40 * rod = fur`, `fortnight = 2 * week`.
  It covers prefixes, compound units, and game-specific units added in the same syntax. UCUM was
  rejected: its [license](https://ucum.org/license) forbids adding units, forbids using it to build
  another units standard, and is revocable.
- **Expressions:** a closed, non-Turing-complete language. Parameter references, arithmetic,
  comparison, a conditional, `min/max/floor/ceil/round/clamp`, vector helpers (`distance`, `lerp`),
  and unit expressions, all parsed by the same grammar. No user-defined functions, no loops, no
  recursion. In JSON they're strings, parsed once in C++ into a cached syntax tree. Not Godot's
  `Expression` class, which can call methods.
- **Generators** are named, deterministic C++ functions that yield *frames*. `repeat`/`split` runs
  along an axis with CityEngine-style absolute, relative and floating sizes and **explicit fit
  modes** (`stretch`, `center`, `clip`, `exact`). CityEngine's default of silently clipping the last
  element would leave half-merlons.
- **Predicates** are named world queries for step preconditions (`area_clear(box)`,
  `solid_at(cell)`), implemented in the engine, never written inline.
- **Determinism:** evaluated transforms are canonicalised to a snap epsilon, so repeats stay
  symmetric.
- **One evaluator, two hosts (to investigate).** CoffeeScript tools also need to evaluate
  expressions (previews, linting). Rather than write the grammar twice, build the C++ evaluator as a
  Node-API addon, or compile it to WebAssembly, so the tools call the engine's own code. Robert notes
  that Node's C/C++ integration keeps maturing. Unverified; decide when the evaluator exists.

## Format 1: field captures (the bitmap)

"Snapshot" is already taken (`WorldSnapshot`, the F5 save), so these are **field captures**.

- **What:** the output of `fill_region` and `fill_indices_region` over a region. That's the SDF as
  float32 and the material as uint8 at the same lattice points, stored with metadata (origin, cell
  size, dim, generator parameters, sampling convention). The file is an `.npz`, which numpy and
  Blender scripts can read and GDScript can write through `ZIPPacker`.
- **Why:** bit-exact and independent of the generator. GUT compares captures with `==` on packed
  arrays.
- **The EditStore blob stays the *tree* fixture.** It's exact only relative to a bit-identical
  `TerrainField`, so it carries a generator fingerprint (a few recorded samples). A changed generator
  then refuses the fixture instead of silently changing what it means.
- **Blender:** `tools/capture_to_vdb.py`, run inside a blender.org Blender, writes a float SDF grid
  and an int material grid (never tagged as a level set, since our SDF isn't a true distance;
  half-float off). It's Python because it runs inside Blender. Robert's Devuan Blender 4.3.2 lacks
  the `openvdb` module, so a blender.org build is needed. **OpenVDB is not linked into the engine**,
  and VDB is never a fixture: our octree can't be stored in a VDB grid without loss.
- **Meshes:** export the DC mesh as glTF through Godot's built-in `GLTFDocument`, for "what did the
  mesher actually draw."

## Format 2: methods (the commands)

Methods follow HTN, the approach Guerrilla's Decima planner and *Transformers: Fall of Cybertron*
shipped with. We take HDDL's *structure* (tasks, methods, ordering, typed parameters) and none of its
Lisp syntax.

- **Tasks** decompose through **methods** into primitive **steps**. A step is one of our Actions
  with resolved arguments (`dig`, `csg`, `build`, ...), plus test-only steps: `player_at`,
  `advance(frames)`, `settle`, `mark(note)`.
- **Goals** (state predicates such as `area_clear`) can be mixed with tasks, as in GTPyhop. A goal is
  checked after its steps; **in a test, that check is the assertion.**
- **Ordering:** authoring allows `unordered` blocks ("four walls in any order, then the roof"). The
  runtime planner linearizes them (top-down, strictly ordered, the way every shipped game planner
  found works), and a recording that built the walls in any order still validates against the method.
- **Repetition:** parameters come from generators (`each seg in wall_segments(...)`), or from
  recursion when the count depends on world state ("keep clearing until `area_clear`").
- **Recordings store bound values**, so replays are exact. The same generator can be re-run to check
  it still produces those bindings, a separate regression gate.
- **JSON numbers:** `JSON.stringify` defaults to about 14 significant digits (lossy for doubles) and
  writes -0.0 as "0.0". Recordings use `full_precision = true`, and a round-trip test must pass first.
- **Four uses of one format:**
  1. Hand-written test scenarios.
  2. Recordings of play.
  3. The process half of an assembly.
  4. Later, the planner's output, when the play layer's directives turn a goal into steps the avatar
     carries out over time ([doc 08](08-continuous-work-actions.md)'s work-action state machine). In
     tests, steps execute instantly.

  The step record is shaped so it could also be the successor game's op-log unit
  ([doc 05](05-network-architecture.md)). That's not a requirement here.

## Assemblies: a method plus a product description

An assembly has two halves:

1. **Process:** a method, meaning ordered, parameterized steps. "Build a stone wall 1 m tall, leave a
   gap, put a gate in the gap."
2. **Product:** a declared description of the finished thing: start, end, facing, dimensions,
   materials, mass, pathing, and named **anchors** (`door.hinge`, `wall.end`). Other systems query
   this without re-running the steps; the planner, pathing and placement all need it.

Parametric CAD works the same way: FreeCAD and SolidWorks keep a feature history, re-run it to rebuild
the model, and the dimensions you typed become editable parameters. The difference here is that the
history comes from **demonstration**: you build the prototype in the world.

**Order and reach come from the demonstration.** Placing an assembly writes a sequence of shapes, some
adding material and some removing it, and where they overlap the last one wins. A gatehouse shows why
no single format rule could be right:

- A gap can be *left* (wall sections placed either side of a space) or *cut* (a whole wall, then an
  opening removed). Those are different histories with different results where materials meet.
- If the door is imprinted before the opening is cut, the cut deletes it.
- Where an oak lintel's ends are buried in the stone, whichever is written last sets the material.
- Stamped into a hillside, a cut either reaches the terrain (a tunnel entrance) or only the
  gatehouse's own stone (a free-standing gate).

So the recorded order *is* the imprint order, and each cut records the reach it had when the prototype
was built.

**From demonstration to parameters.** The constants in a demonstration become parameters whose
defaults match the original. The hard part, and the area for experiment, is capturing
*relationships*: widening the gap must widen the gate, so that's one parameter, not two.
- **Placements are recorded relative to what they touch,** not in absolute coordinates ("the gate
  sits between the gap's two edges"), which preserves relationships automatically.
- **The builder can name and link dimensions explicitly** where inference can't tell. This fits
  [doc 17](17-consider-and-hypothetical-mode.md)'s naming verb: naming a dimension is how it becomes a
  parameter.
- **What can't be inferred gets asked, not guessed.**

**Everything else carries over:**
- Material inherits from the parent unless set (LDraw's "colour 16").
- Sub-assemblies come in with `use:` + `with:` and attach by anchors.
- A sparse override layer is keyed by evaluated path (`"merlon[7]": {omit: true}`), borrowed from
  USD's `over`. That's how later edits and damage are recorded against a parametric original.
- Rotation is a quaternion or axis-angle, never an enum or a part-type variant.
- A `format:` version and a part registry with aliases.

**Evaluation** re-runs the process with bound parameters and yields a flat list of
`(path, part, material, transform, size)` to imprint. **PartIndex can key parts by path**, which may
answer [`part-index-sub-cell-parts-untracked`](../../bugs/part-index-sub-cell-parts-untracked.md):
identity by path, not by cells. **Doc 17's concept library is this format on the play side**: a
named build is an assembly, and sharing one means exporting its JSON.

Sketch of the authoring side (CoffeeScript, emitting the JSON):

```coffee
assembly 'gatehouse',
  params:
    width: m 10, height: m 7, thickness: m 2, gate_w: m 3, gate_h: m 4, material: 'cemented_stone'
  process: [
    add 'wall', part: 'stone_block', size: ['width', 'height', 'thickness']
    cut 'opening', box: ['gate_w', 'gate_h', 'thickness'], at: anchor('wall.base_center'), reach: 'self'
    use 'door', fit: 'opening', material: 'oak'
  ]
  product:
    anchors: start: [0, 0, 0], end: ['width', 0, 0], gate: 'opening.base_center'
```

## The record → test loop

1. **Hook:** every gameplay action runs `validate()` and `execute()` in one place, `player.gd`.
   Record there, not at construction: `voxel_preview_renderer.gd` constructs an action every frame.
   Each step records its resolved arguments, the player's position (the safety checks read it), the
   physics frame, and the result of `validate()`.
   - Copy CSG's live shape object by value.
   - Record a construction part's path and dimensions.
   - Record the `mpmthaw` console command as a step too.
2. **`rec start`** requires the world to be settled (the same gate as F5) and captures the starting
   blob. **`rec fresh`** starts from the generator alone, which reproduces most reliably.
3. **`mark [note]`** saves the camera, FOV, dcworld settings, the aimed cell with its probe report, and
   a screenshot. That turns "this looks wrong" into something an assertion can be written from.
4. **Replay runner** (GUT, headless, no World scene): the simulations tick explicitly at 1/60 s,
   never on wall-clock time, and replay **stops at the first step whose result differs from the
   recording**, the lesson from Riot's determinism work. This needs tick functions on DetachmentScout
   and StructuralIntegrity.
5. **Trim** by deleting steps; once an assertion exists, an automatic delta-debugging (ddmin) pass can
   shrink it. A new scenario test starts `pending` and must fail on the buggy code before the fix goes
   in. Recordings are never used as approval snapshots, because that would lock in the bug.

**Gaps to close first:**
- Saves don't keep PartIndex.
- DetachmentScout's pending work is missing from `is_quiescent()`.
- MPM orders its freeze by camera distance, which makes structural event order depend on the camera.
- A fresh `mesh_world` doesn't exercise the live incremental mesher, so render bugs in that path need a
  camera-path replay.

## The instrument layer (test tools)

These are grid-aware and deliberately non-diegetic. They replace FillVoxel, EmptyVoxel and the rest as
instruments.

- **Inspect:** the probe also reports the owning leaf, its size and field state, all 8 corner values,
  and the mesher's sign test, with an optional overlay of leaf boundaries and corner signs.
- **Set exactly:** console writes through the normal EditStore path, so the edit renders and emits
  events like any edit. Examples: set a cell's 8 corners, set a cell's material, stamp a typed CSG
  shape by numbers. They bypass player safety, switching the player to fly mode when needed (see
  Decisions).
- **Named saves** (`save <name>` / `load <name>`), and commands to export and import assemblies.

## Build order

Each phase is gated by GUT and ships on its own.

1. **Instrument layer + step language + recorder + replay runner** (GDScript). This pays off at once
   in tests.
2. **Field captures + the Blender script + glTF mesh export.**
3. **C++ expression evaluator with units + assemblies authored as methods** (steps, `use:`, anchors,
   a product description). A cabin can be exported, imported and stamped into a new world. Then
   parameters, repeats and overrides.
4. **Prototype by demonstration:** turn a recording into a parameterized assembly, with
   relative-placement capture and naming. This is the experimental phase.
5. **HTN planner + directives** (the play layer). It belongs with the directives work; the phases
   above don't wait for it.

## Dependencies this introduces

| Dependency | Why | When |
|---|---|---|
| Node (latest) | runs the CoffeeScript tools in `tools/` | with the first tool |
| CoffeeScript 2.7 | authoring surface; the project's preferred tooling language | as above |
| Pint unit definitions (data file, BSD-3-Clause, vendored) | the unit table: names, aliases, prefixes, conversions | phase 3 |
| Blender from blender.org (optional) | bundles the `openvdb` Python module that `capture_to_vdb.py` needs | phase 2, for viewing captures only |

The project has no dependency list yet. The first of these to land should create one, recording each
dependency and why it exists.

## Open questions

- **Relationship capture** in prototype-by-demonstration: which relationships can be inferred from
  relative placement, and what the naming and linking interaction looks like. This is expected to be
  the long experimental thread.
- **The product description:** which traits are declared by the author, which are derived by
  evaluation (dimensions, mass), and which are computed on demand (pathing)?
