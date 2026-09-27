# Assembly description format — prior art survey

*Drafted by Claude (research agent), 2026-09-26. Web research; "Verified" = read on the
cited page this session. "Inference" = my reasoning, not a sourced claim.*

## TL;DR

- No existing format does what we need (semantic parts + real parameters + repeats +
  sub-assembly refs) in a lightweight, open, data-only form. Each source contributes one
  piece:
  - **USD** → the *composition vocabulary*: references, instancing, variants, sparse
    per-path overrides, layers. But USD has **no arithmetic**; it cannot express "count =
    floor(length / pitch)".
  - **LDraw** → proof that "part-id + color + 4x3 transform + sub-model reference, one per
    line" is enough for a huge ecosystem. Zero parameterization.
  - **CGA (CityEngine)** → the *repeat model*: split along an axis with absolute /
    relative / floating sizes and `*` repeat-to-fit. This is exactly the battlement
    problem.
  - **OpenSCAD / build123d / CadQuery** → parameters and loops, but as a general
    programming language. Good for the authoring side, wrong for the data side.
  - **Minecraft / Sponge / Space Engineers / KSP / Besiege / Stormworks** → the cautionary
    tales: grid-locked rotation enums, orientation-in-block-state bugs on rotate, data
    versioning pain, and nobody has parameters.
- Recommendation: YAML with (1) typed params with units and defaults, (2) a tiny,
  non-Turing-complete arithmetic expression language, (3) a CGA-style `repeat`/`split`
  along a local axis, (4) `use:` sub-assembly references with param bindings (USD
  reference + LDraw type-1 line), (5) path-addressed sparse overrides for player edits
  (USD `over`), (6) a format version + migration chain from day one (Minecraft
  DataVersion lesson). Evaluate in-engine to a flat placement list; the flat list is what
  gets imprinted. CoffeeScript is for authoring/linting tools, not the canonical form.

---

## 1. OpenUSD

### Verified
- **AOUSD Core Specification 1.0** was announced 2025-12-17 as a ratified standard. It
  covers the foundational data model, composition/value resolution, and the USDA / USDC
  / USDZ formats. **Geometry, materials and physics are explicitly out of scope** ("in
  development" as separate domain specs). A 1.1 is being worked on for 2026 (animation,
  scaling, compliance testing).
  - https://aousd.org/news/core-spec-announcement/
  - https://www.linuxfoundation.org/press/alliance-for-openusd-announces-core-specification-1.0-the-universal-language-for-building-3d-worlds
  - https://www.cgchannel.com/2025/12/aousd-releases-the-first-openusd-core-specification/
  - So yes: there is now a formal "USD core" that is shading-free *by construction*. I did
    not read the spec document itself or confirm its license (download link is a bit.ly
    from the announcement). **Unsure** on spec text license.
- **Composition arcs (LIVERPS)**: Local (sublayers), Inherits, VariantSets, Relocates,
  References, Payloads, Specializes — in strength order.
  - https://openusd.org/release/glossary.html
  - https://docs.nvidia.com/learn-openusd/latest/creating-composition-arcs/strength-ordering/what-is-liverps.html
  - Payloads = references that can be unloaded at runtime (LOD/streaming concept).
  - Encapsulation: whatever a reference/variant/etc. brings in is immutable from above
    except via stronger opinions at the same path (overrides).
- **Instancing**: two kinds. *Scenegraph instancing* (`instanceable = true` on a prim
  with composition arcs; USD dedupes into implicit prototypes, instance subtrees are
  read-only) vs *PointInstancer* (explicit prototypes + arrays of positions/orientations/
  protoIndices; instances addressed by index, not path; per-instance edits limited to
  schema attributes).
  - https://docs.nvidia.com/learn-openusd/latest/asset-modularity-instancing/instancing-faq.html
  - https://openusd.org/dev/api/class_usd_geom_point_instancer.html
- **Variable expressions** are the only "computation" in USD: `${VAR}` substitution,
  comparisons, `if/and/or/not`, `contains`, `len`, etc. **No arithmetic.** Usable only in
  asset paths and variant selections — **not** in attribute values like a length or
  count.
  - https://openusd.org/release/user_guides/variable_expressions.html
- **License**: OpenUSD source is under the Tomorrow Open Source Technology license
  (Apache 2.0 with a modified trademark clause).
  - https://github.com/PixarAnimationStudios/OpenUSD/blob/release/LICENSE.txt
- **Lightweight implementation**: TinyUSDZ (MIT, C++14, dependency-free, reads/writes
  USDA/USDC/USDZ; composition support "experimental / basic").
  - https://github.com/lighttransport/tinyusdz
- **Godot**: no native USD. Proposal still open
  (https://github.com/godotengine/godot-proposals/issues/7744; discussion #5469, #7436).
  Community: `tefusion/godot-usd` (import via TinyUSDZ, "basic scenes from Blender"),
  `V-Sekai/godot-usd` (round-trips through Blender).
  - https://github.com/tefusion/godot-usd
  - https://github.com/V-Sekai/godot-usd

### Fit for us (inference)
- **Borrow the concepts, not the file format.** References (sub-assembly), variants
  (enum params like `style: [plain, battlemented]`), sparse overrides at a path (player
  removed merlon #7), instancing (every merlon shares one prototype), payload (load the
  detail of a far-away castle lazily) all map cleanly.
- **Do not adopt USDA as the canonical format.** The parameter problem is the core
  requirement and USD cannot express it; we'd end up with USD-plus-a-sidecar-DSL, which is
  worse than one format. Full LIVERPS (inherits, specializes, relocates, strength
  ordering across layer stacks) is a large semantic surface that we don't need; its
  debugging cost is well known in film pipelines. Godot support doesn't exist anyway.
- A reasonable *export* target later: flattened, evaluated assemblies → USDA with
  prims per part and custom attributes (`voxel:partType`, `voxel:material`) for
  interchange with Blender/Houdini. That's cheap because it's one-way and post-evaluation.

## 2. LDraw

### Verified
- Line-oriented text. Line type 1 is a subfile reference:
  `1 <colour> x y z a b c d e f g h i <file>` — position plus the 3x3 of an affine
  transform. Colour 16 = "inherit the referencing line's colour". Meta commands are
  `0 !<META> ...`. **No parameters or variables**; only direct file references.
  - https://ldraw.org/article/218.html
- MPD (multi-part document) packs several sub-models into one file (a documented
  language extension). https://ldraw.org/docs-main.html
- License: parts are CC BY 4.0 (or CC0 by author choice); OMR models must carry
  `0 !LICENSE Licensed under CC BY 4.0`.
  - https://www.ldraw.org/pt-policies.html , https://www.ldraw.org/legal-info
- The only "parametric" thing in the ecosystem is external: **LSynth** synthesizes
  bendable parts (hoses, chains, treads) from control points written into the file as
  meta-command blocks, then expands them to ordinary parts.
  - https://github.com/deeice/lsynth , https://wiki.ldraw.org/wiki/Custom_LDraw_File_Syntax_Additions

### Fit for us (inference)
- LDraw's flat line = our **evaluated** output shape almost exactly: `(partType,
  material, transform)` with material inheritance. Colour 16 → a `material: inherit`
  default is worth copying (a door assembly takes the cabin's wood unless it says
  otherwise).
- The LSynth pattern (parametric generators emit plain placements, stored as a marked
  block the tool can regenerate) is essentially what we want, but promoted to a
  first-class feature.
- Nothing to adopt as a dependency. The data is Lego-specific.

## 3. Procedural / parametric description

### CGA shape grammar (Esri CityEngine) — the most relevant
- Verified syntax (https://doc.arcgis.com/en/cityengine/latest/cga/cga-split.htm):
  `split(axis) { size : op | size : op ... }` with optional `*` for repeat. Size prefixes:
  absolute `3.3`, relative `'0.5` (fraction of scope), floating `~3` (stretched to absorb
  the remainder). Example `split(x){ 2 : X | 1 : Y }*` repeats until the scope is full,
  clipping the last. Scopes are oriented boxes; rules recursively subdivide them.
  Also `comp` (split into faces), `extrude`, `i(asset)` insert.
- License: CityEngine is commercial. The C++ SDK / Procedural Runtime is free for
  non-commercial use, commercial use needs a CityEngine license, no redistribution
  unless permitted. Palladio (Houdini) and Serlio (Maya) plugins are open source but
  still require the proprietary PRT. https://github.com/Esri/cityengine-sdk ,
  https://esri.github.io/cityengine/cityenginesdk
  - **Not usable as a dependency.** The *ideas* are published (Müller et al. 2006,
    "Procedural Modeling of Buildings") and freely borrowable.
- Open-source implementations are toys/partial: LudwikJaniuk/cga-shape (simplified),
  mashenjun/CGA-Shape-grammar-parser (parser only), CGAjs ("very small subset").
  https://github.com/LudwikJaniuk/cga-shape , https://gromgull.github.io/cgajs/ .
  Research relative: box-split grammars for Minecraft architecture
  (https://dl.acm.org/doi/fullHtml/10.1145/3555858.3555865). None worth depending on.
- Fit (inference): **Borrow the split/repeat semantics verbatim** — especially floating
  sizes and repeat-to-fit. A battlement is literally `split(x){ merlon_w : Merlon |
  crenel_w : Crenel }*` inside the parapet scope. Two things CGA does that we should *not*
  copy: (a) the implicit "clip the last element" behavior (a half-merlon is a bug for us;
  we want explicit fit modes: `stretch`, `center`, `clip`, `exact-or-error`), and (b) the
  full rule-rewriting grammar with stochastic rules and conditionals — that's a language,
  and it pulls toward "procedural city generator" rather than "a thing a player places".

### OpenSCAD
- GPL-2.0-or-later program. Parameters are top-level variables; `module` with
  `children()` gives composable parts; `for` loops in modules; functions are pure (list
  comprehensions / recursion, no loops in function bodies). Manifold backend (much faster
  CSG) landed in dev snapshots late 2024; the long-stalled stable release still uses CGAL
  as of the sources I found — **unsure** whether a 2025/2026 stable shipped with Manifold
  default. https://en.wikipedia.org/wiki/OpenSCAD ,
  https://github.com/openscad/openscad/pull/4533 ,
  https://en.wikibooks.org/wiki/OpenSCAD_User_Manual/User-Defined_Functions_and_Modules
- Fit (inference): the *mental model* (union/difference of box/cylinder/sphere with
  transforms, driven by parameters) is uncannily close to our imprint model. But the
  output of OpenSCAD is a mesh; it loses part identity. Using it as the format means
  embedding an interpreter. Borrow: `module`-with-params-and-children as the shape of an
  assembly definition. Avoid: the full language; also its dynamic-scope `$vars`, which
  are a known source of confusion.

### CadQuery / build123d
- CadQuery: Apache-2.0, Python over OpenCascade (OCCT, LGPL). build123d: Apache-2.0,
  derived from CadQuery, context-manager builders (`BuildPart`) and location generators
  (`GridLocations`, `PolarLocations`, `Locations`) for repeats.
  https://github.com/CadQuery/cadquery/blob/master/LICENSE , https://github.com/gumyr/build123d
- Fit (inference): the **location-generator** idea (a repeat is "a list of transforms",
  separate from what is placed at them) is a clean decomposition worth copying — our
  `repeat` should produce frames, and the body places parts into each frame. Heavy
  (OCCT, B-rep), Python, mesh/BRep output. Not a dependency.

### Blender Geometry Nodes
- Inference / general knowledge, not re-verified this session: GPL (Blender), node graphs
  live only inside .blend files, no standalone spec or runtime; "Instance on Points" +
  "Realize Instances" is the instancing model; exposed group inputs are the parameter
  model. Fit: none as a format. Possibly useful later as an authoring preview tool via a
  Python exporter.

### IFC (Industry Foundation Classes)
- IFC 4.3 = ISO 16739-1:2024, open standard (buildingSMART, CC-licensed docs).
  Relevant entities: `IfcExtrudedAreaSolid` (profile swept by depth — i.e. "wall from A
  to B, thickness t, height h" is a first-class parametric solid), `IfcBooleanResult`
  (CSG), `IfcRepresentationMap` + `IfcMappedItem` (define once, place many with a
  transform = instancing). IfcOpenShell toolkit is LGPL-3.0-or-later.
  https://ifc43-docs.standards.buildingsmart.org/IFC/RELEASE/IFC4x3/HTML/lexical/IfcExtrudedAreaSolid.htm ,
  https://ifc43-docs.standards.buildingsmart.org/IFC/RELEASE/IFC4x3/HTML/lexical/IfcMappedItem.htm ,
  https://docs.ifcopenshell.org/introduction.html
- Fit (inference): IFC stores *evaluated* parametric geometry, not the *rules* (there is
  no "repeat merlons every 2.5 m" — you'd get N mapped items). Its STEP/EXPRESS encoding
  and semantic surface (IfcWall, IfcRelAggregates, property sets...) are enormous. Borrow
  two ideas: the **wall-as-profile-swept-along-a-path** primitive, and semantic *kinds*
  (wall, slab, door) as tags on assemblies. Avoid everything else.

## 4. Voxel / construction game precedents

| Game / format | Shape | Rotation | Params | Reported pain |
|---|---|---|---|---|
| Minecraft structure `.nbt` (Java) / `.mcstructure` (Bedrock) | size + palette + block list, `DataVersion` | Applied at placement: NONE/CW90/CW180/CCW90 + mirror LEFT_RIGHT/FRONT_BACK | None; composition via jigsaw blocks + template pools + processors (random selection, block replacement) | Directional block states must be rewritten on rotate; DataVersion upgrades |
| Sponge `.schem` v3 (WorldEdit) | palette of `id[k=v]` strings + varint array, `DataVersion` | **Not in format** | None | Stair/directional blocks face wrong after rotate/paste (many WorldEdit issues) |
| Space Engineers `bp.sbc` | XML `MyObjectBuilder_CubeBlock` with `Min` grid cell | `BlockOrientation Forward=.. Up=..` (24 axis-aligned) | None | Grid-only; huge verbose XML |
| KSP `.craft` | ConfigNode text, PART blocks with `pos`, `rot` (quaternion), `attN` attach nodes, symmetry links | Free quaternion | None (symmetry is the only repeat) | Mods/part renames break craft files |
| Besiege `.bsg` | XML, Position + Rotation quaternion + Scale per block | Free quaternion | None | Float imprecision breaks symmetry (community guide on it) |
| Stormworks vehicle XML | per-component 3x3 `r=` matrix | Axis-aligned matrix (XML-hacked to non-orthogonal) | None | People hand-edit XML to get non-grid angles |

Sources: https://minecraft.wiki/w/Structure_Block ,
https://wiki.bedrock.dev/nbt/mcstructure.html , https://minecraft.wiki/w/Jigsaw_structure ,
https://minecraft.wiki/w/Template_pool ,
https://github.com/SpongePowered/Schematic-Specification/blob/master/versions/schematic-3.md ,
https://github.com/EngineHub/WorldEdit/issues/2076 ,
https://github.com/AllTheMods/ATM3-Remix/issues/239 ,
https://spaceengineers.wiki.gg/wiki/Modding/Reference/SBC ,
https://wiki.kerbalspaceprogram.com/wiki/CFG_File_Documentation ,
https://forum.kerbalspaceprogram.com/topic/51800-any-doco-on-the-craft-file-format/ ,
https://steamcommunity.com/sharedfiles/filedetails/?id=762216645 (Besiege float symmetry) ,
https://steamcommunity.com/sharedfiles/filedetails/?id=3350900327 (Stormworks matrix).

Lessons (inference from the above):
1. **Orientation must live in the transform, never in the part's type/state.** Minecraft's
   `facing=north` block state is why rotated schematics break. Our parts are CSG with a
   transform, so we're already on the right side — keep it that way (no "beam_north"
   part types).
2. **Store rotation as a quaternion (or axis+angle for authoring), not Euler, not enums.**
   Enum orientations are the grid-game trap. Besiege shows free quaternions + floats
   need canonicalization for symmetry; so generate repeats by *evaluating* from params
   rather than storing N copies, and round evaluated transforms to a snap epsilon.
3. **Version the format and the part registry from day one** with a migration chain
   (Minecraft `DataVersion` + DataFixer; KSP breaks on part renames). Part types should
   be referenced by stable ids, with an alias table for renames.
4. **Nobody has parameters.** Minecraft's closest thing is jigsaw/template-pool
   composition (random choice of sub-structures at connectors) plus processors (block
   substitution). That's a *world-gen* mechanism, not a player-authored parametric one.
   There's no precedent to copy here — this is where CGA is the model.
5. **Attach points** (KSP `attN`, Minecraft jigsaw blocks) are how sub-assemblies snap
   together without absolute coordinates. Worth copying: named anchors on assemblies
   (`door.hinge`, `wall.end`), so a cabin places its door by anchor, not by magic numbers.

## 5. Recommendation

### Borrow
| Concept | From | Our form |
|---|---|---|
| Sub-assembly reference with transform | USD reference, LDraw type-1 line | `use: door` + `at:` frame + `with:` param bindings |
| Material inheritance | LDraw colour 16 | `material: $material` default, child inherits unless set |
| Enum choices | USD variant sets | `enum` params |
| Sparse per-instance edits at a path | USD `over` / layers | `overrides:` keyed by evaluated path, e.g. `parapet/merlon[7]: {omit: true}` |
| Shared prototypes | USD instancing / IFC mapped item | implicit: identical (type, params) → one evaluated prototype |
| Lazy load of detail | USD payload | later: far assemblies imprint coarse; evaluate detail on approach (ties into the world-builds-on-attention idea) |
| Split / repeat-to-fit with absolute/relative/floating sizes | CGA | `split:` / `repeat:` along a local axis, explicit `fit:` mode |
| Repeat produces frames, body places into frames | build123d location generators | `repeat` yields `i`, `n`, local frame |
| Parameters with defaults, modules with children | OpenSCAD | `params:` block |
| Named anchors / attach nodes | KSP attN, Minecraft jigsaw | `anchors:` on assemblies |
| Wall = profile swept A→B | IFC ExtrudedAreaSolid | `frame: {from: $A, to: $B}` sets local x along A→B |
| Format + registry versioning, migrations | Minecraft DataVersion | `format: 1`, part ids + alias table |

### Avoid
- A Turing-complete language in the data (OpenSCAD, full CGA grammar, Python). The
  YAML must be evaluable in-engine (C++ or GDScript), safely, deterministically, when a
  player drags a wall endpoint. Expressions: arithmetic, comparisons, `min/max/floor/
  ceil/round/clamp`, param refs, `i`/`n` in repeats. No user-defined functions, no
  recursion except sub-assembly nesting with a depth limit and cycle detection.
- Full USD composition (inherits, specializes, relocates, multi-layer strength ordering).
- Orientation encoded in part type or state (Minecraft).
- Euler angles in the canonical form.
- Implicit clipping of the last repeat (CGA default) — silent half-merlons.
- Storing the evaluated expansion as the source of truth (IFC, every game format). Store
  params; the expansion is a cache, reproducible.

### CoffeeScript's role (inference / opinion)
Making a CoffeeScript DSL the source and YAML the compiled output would put the
parameters in CoffeeScript and leave YAML as a flat list — which defeats in-game
re-parameterization (player drags the wall's end point; the game must re-evaluate). So:
**YAML with params + expressions is canonical and evaluated in-engine.** CoffeeScript
tools are for linting, previewing, batch-generating assembly libraries, and maybe a
builder API that *emits* parameterized YAML (not expanded YAML). If a CoffeeScript
evaluator exists for tooling, the same expression grammar must be implemented twice
(engine + tool) — share a conformance test corpus of (assembly, params) → expected flat
placement list.

Note: Godot's built-in `Expression` class can evaluate arithmetic strings, but it can
also call methods on a base instance and builtin functions; I did not verify its exact
sandbox surface. A small hand-written expression parser in C++ is the safer, portable
choice (inference).

### Open design questions surfaced by the example
- The phrase "crenels 1 m at the lows and 2 m at the highs and 0.5 m gaps" is ambiguous.
  I read it as: parapet is 1 m tall at the crenels (lows), 2 m tall at the merlons
  (highs); 0.5 m crenel width. Merlon width was not given, so it's a parameter with a
  default. Real natural-language input will be ambiguous like this; named parameters are
  the disambiguation.
- "3 m platform on top" of a 2 m wall: overhangs 0.5 m each side, or one side? Made it
  `platform_overhang_inner/outer` params.
- Crenels as *additive merlons on a low parapet* vs *subtractive gaps from a full
  parapet*: additive is better for PartIndex (each merlon is a real part a player can
  knock down), so the example is additive.

### Sketch

```yaml
format: 1
assembly: curtain_wall
kind: wall                       # semantic tag (IFC-style), optional
params:
  A:          {type: point}                      # world or parent-frame points
  B:          {type: point}
  thickness:  {type: length, default: 2 m}
  height:     {type: length, default: 7 m}
  material:   {type: material, default: cemented_stone}
  platform:   {type: length, default: 3 m}       # walkway width on top
  platform_t: {type: length, default: 0.4 m}
  overhang_outer: {type: length, default: "(platform - thickness) / 2"}
  battlements:
    side:       {type: enum, of: [outer, inner, none], default: outer}
    low:        {type: length, default: 1 m}     # parapet height at crenels
    high:       {type: length, default: 2 m}     # merlon height
    gap:        {type: length, default: 0.5 m}   # crenel width
    merlon_w:   {type: length, default: 1.5 m}
    depth:      {type: length, default: 0.5 m}
frame: {from: $A, to: $B, up: +y}                # local x = A->B, length = L
derived:
  L: "distance(A, B)"
anchors:
  start: {at: [0, 0, 0]}
  end:   {at: [$L, 0, 0]}
  walk:  {at: [0, $height + $platform_t, 0]}

parts:
  - id: core
    part: stone_block                            # CSG box, registry id
    size: [$L, $height, $thickness]
    at:   [$L/2, $height/2, 0]
    material: $material

  - id: platform
    part: stone_slab
    size: [$L, $platform_t, $platform]
    at:   [$L/2, $height + $platform_t/2, $overhang_outer - ($platform - $thickness)/2]
    material: $material

  - id: parapet                                  # the low run under the crenels
    when: "battlements.side != 'none'"
    part: stone_block
    size: [$L, $battlements.low, $battlements.depth]
    at:   [$L/2, $height + $platform_t + $battlements.low/2, $parapet_z]

  - id: merlon
    when: "battlements.side != 'none'"
    repeat:                                      # CGA split, explicit fit
      axis: x
      over: [0, $L]
      pattern: [{size: $battlements.merlon_w, emit: true},
                {size: $battlements.gap,      emit: false}]
      end_with: emit                             # wall starts and ends on a merlon
      fit: stretch_gaps                          # stretch | center | clip | exact
    part: stone_block
    size: [$cell.size, $battlements.high - $battlements.low, $battlements.depth]
    at:   [$cell.center, $height + $platform_t + $battlements.low
                         + ($battlements.high - $battlements.low)/2, $parapet_z]

  - id: gate
    use: door_assembly                           # sub-assembly reference
    with: {width: 2.5 m, height: 4 m, material: oak}
    attach: {its: base_center, to: [$L/2, 0, 0]}
    cut: true                                    # carve an opening in `core`

derived_more:
  parapet_z: "battlements.side == 'outer' ? -(platform/2 - battlements.depth/2) : (platform/2 - battlements.depth/2)"
```

Placing one and a later player edit (a separate, sparse layer — USD `over` idea):

```yaml
format: 1
instance: north_wall
use: curtain_wall
with: {A: [0,0,0], B: [42,0,0], battlements: {side: outer}}
overrides:
  "merlon[7]": {omit: true}           # knocked down by a trebuchet
  "merlon[8]": {material: rubble}
```

Evaluation produces a flat, LDraw-like list — the imprint input and the PartIndex keys:

```
north_wall/core        stone_block  cemented_stone  T(...)  size(42, 7, 2)
north_wall/merlon[0]   stone_block  cemented_stone  T(...)  size(1.5, 1, 0.5)
...
north_wall/gate/leaf   plank        oak             T(...)
```

Caveats on the sketch: the ternary in `parapet_z` shows the expression grammar needs a
conditional; `derived_more` split is an artifact of writing it top-down (real format
should allow derived values anywhere with dependency ordering and cycle errors); `$cell`
is the implicit per-repeat frame. `cut: true` implies subtractive CSG ordering between a
sub-assembly and its parent — imprint order is a semantic of the format and must be
specified (union first, then cuts, then children?), not left to evaluation order.
