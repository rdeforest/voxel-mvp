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

- **Values:** number, length, angle, point, frame, material, part type, enum, bool, cell, count
  (a whole number of at least zero, e.g. `advance`'s frames; added by Claude, G4.2).
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
- **Step shape** (phase 1, 2026-09-27): `{"op": <name>, ...the action's resolved constructor
  arguments}`, one step per line of a file headed `{"format": "voxel-mvp/steps", "version": 1,
  "units": {"length": "meter", "angle": "degree"}}`. Vectors are `[x, y, z]`, transforms
  `{"basis": [x, y, z], "origin": [...]}` (Godot's basis vectors), enums and materials by name.
  A CSG step holds the shape by value (`shape` + `dims`); a build step holds the part's file *and*
  its dimensions, and a file whose part changed size is refused rather than replayed. Recorded
  numbers are the engine's own metres and degrees; the unit strings above are for quantities a
  person writes and arrive with the phase-3 evaluator.
- **Recordings store bound values**, so replays are exact. The same generator can be re-run to check
  it still produces those bindings, a separate regression gate.
- **JSON numbers:** `JSON.stringify` defaults to about 14 significant digits (lossy for doubles) and
  writes -0.0 as "0.0". Recordings use `full_precision = true`, and a round-trip test must pass first.
  *Measured 2026-09-27 (Claude, G4.0), on this engine (4.6, double build): that test fails.
  `full_precision` still reads 24% of random doubles back an ulp off, and `var_to_str` 31%;
  `var_to_bytes` is exact (100,000 samples each, `scripts/dev/probe_var_to_str_precision.gd`). The
  step format needs an exact number encoding before G4.1 can gate on the round trip.*
  *Resolved 2026-09-27 (Claude, G4.1): the loss is all on the reading side. The `full_precision`
  text is the engine's Grisu2 output, which a correctly rounding parser reads back exactly (Python,
  200,000 doubles over every exponent including subnormals, `scripts/dev/probe_grisu_vs_python.gd`);
  the engine's `String::to_float`, shared by JSON and GDScript literals, is off by an ulp on about
  a quarter of them and reads `2.2250738585072014e-308` as zero. So step files stay plain JSON with
  shortest-round-trip numbers, which any correct reader (Python, Node) takes exactly, and
  `StepJson` reads each number from its own text: the engine's value when its own Grisu2 text
  matches, otherwise correct rounding by exact big-integer comparison (`ExactDecimal`). `-0.0` is
  written with its sign. Reading costs about 10–20 µs per number at game magnitudes
  (`scripts/dev/probe_exact_decimal_cost.gd`). The alternatives were worse for a file people trim
  by hand: `var_to_bytes` is exact but not text, and hex floats are text nobody reads.
  A duplicate key anywhere is refused: the engine keeps a duplicate at its first position with its
  last value, so numbers re-read in document order would land on the wrong keys. GDScript folds a
  literal `-0.0` to `+0.0` in some expressions (`[-0.0][0]`, a function argument), so tests build
  it from bits.*
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
   *Built 2026-09-27 (Claude, G4.3): `ScenarioRecorder` + console `rec start|fresh|stop [name]` and
   `mark [note]` (`scenes/world/recording_commands.gd`), hooked on `Player.action_validated`, which
   fires between `validate()` and `execute()`. A recording is a directory, `user://scenarios/<name>/`:
   `steps.json`, the save pair `rec start` wrote, and `mark-NNN.json` (+ `.png`) per mark, which the
   mark step names as `"capture"`. The frame and the player's position are steps of their own
   (`advance`, `player_at`), emitted only when they changed, so the action steps keep their strict
   shape. Time is the frames the simulations ticked, not the engine's physics frame count: the open
   console pauses the tree. The console `settle`, which drains support at once, is recorded as
   `{"op": "drain_support"}`.*
4. **Replay runner** (GUT, headless, no World scene): the simulations tick explicitly at 1/60 s,
   never on wall-clock time, and replay **stops at the first step whose result differs from the
   recording**, the lesson from Riot's determinism work. This needs tick functions on DetachmentScout
   and StructuralIntegrity.
   *Built 2026-09-27 (Claude, G4.2): `test/support/scenario.gd`. Its builder (`s.dig(...)`,
   `s.player_at(...)`, `s.advance(n)`, `s.settle()`, `s.mark(note)`, ...) writes each step, reads it
   back from its JSON and runs what it read, so a built scenario and its replay take one path. An
   action step carries `expect_valid`; the other steps are `{"op": "player_at", "position"}`,
   `{"op": "advance", "frames"}`, `{"op": "settle"}` (frame by frame until `is_quiescent()`),
   `{"op": "mark", "note"}` and `{"op": "thaw", "center", "radius"}`. A scenario starts from the
   generator or from a save pair, not a lone blob, which would drop part identity and tracked
   support. Building it found the snapshot storing support and the player as lossy text; both are
   exact bytes now (snapshot v10). The event bus is global and events carry no world, so two live
   scenarios would hear each other: the runner allows one at a time.*
5. **Trim** by deleting steps; once an assertion exists, an automatic delta-debugging (ddmin) pass can
   shrink it. A new scenario test starts `pending` and must fail on the buggy code before the fix goes
   in. Recordings are never used as approval snapshots, because that would lock in the bug.

**Gaps to close first:**
- ~~Saves don't keep PartIndex.~~ Closed 2026-09-27 (G4.0): the snapshot carries the index
  (records, ancestry, next id), bit-exact.
- ~~DetachmentScout's pending work is missing from `is_quiescent()`.~~ Closed 2026-09-27 (G4.0),
  along with MPM's not-yet-announced freeze chunks.
- ~~MPM orders its freeze by camera distance, which makes structural event order depend on the
  camera.~~ Closed 2026-09-27 (G4.0): bottom layer first, by position. Camera-first meshing, if
  it's wanted back, belongs in the render's own scheduling, not in the event order.
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

*Built 2026-09-27 (Claude, G4.4), except the probe's leaf read-out, the overlay, and assembly
export/import (assemblies are phase 3, so that command waits for them):*
- *The probe (`ProbeAction.report()`, which the HUD, the click and `mark` share) adds whether the
  cell's leaf is edited or the generator's, the 8 corner values the mesher samples, its sign test
  (solid corners, and how many of the 12 edges cross zero, as `dc_octree.h` tests an edge), and
  any corner where the cell's own leaf holds a different value than the mesher reads (a seam).
  **Not built: the owning leaf's origin, size and field state.** No EditStore binding exposes a
  leaf, and this chunk can't touch C++; it needs `Dictionary EditStore::leaf_info(Vector3 p)`
  (origin, size, `FieldState`, material, its 8 held corners, its field source). The overlay of
  leaf boundaries and corner signs isn't built either.*
- *Exact writes: console `setcorners <x y z> <c0..c7>` (corner k at cell + (k&1, k>>1&1,
  k>>2&1); the store rounds each to float32), `setmaterial <x y z> <material>`, and
  `stamp <shape> <add|subtract> <material> <x y z> <dims> [<rx ry rz>]` (the CSG tool's dims and
  rotation). Typed numbers are read with `ExactDecimal`, since the console's own parse can land an
  ulp off. Each is an Action with a step op (`set_corners`, `set_material`, `stamp`), written
  through `StoreWrite` / `VoxelImprint` with one matter-changed event credited to `INSTRUMENT`,
  and recorded at its `validate()` like a click. A setmaterial on a cell the generator held stores
  it (only an edited leaf has a material), so between lattice points its field becomes a trilerp
  and a cell's centre can flip; the event carries it.*
- *The rescue: `PlayerSafeAction.danger_of()` (the test `endangered_by()` refuses a player edit
  with) runs on the written field before the write. Burying the player turns on fly with noclip,
  so they can get out; removing their ground turns on fly. X lands, and also drops the noclip the
  rescue turned on (not examine mode's).
  A stamp is refused past 256 m on an axis (its lattice alone would be ~0.3 GB).*
- *Named saves: `SaveSlot`; `user://saves/<name>/` holds a pair like the default slot's, with
  the same refusals. F5 and F9 stay on the default slot. A slot can't be named after the default
  slot's own files (`world.snapshot`, `world.editstore`, or their `.tmp`), which share the
  directory.*

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
