# HTN / PDDL / plan-language research for voxel-mvp

_Researched and drafted by Claude (Opus 5.5), 2026-09-26. Legend: **[V]** = verified
against the cited URL/API this session; **[I]** = my inference or recollection, not
verified; **[?]** = uncertain, check before relying on it._

---

## 1. HDDL, PDDL 3.x, PDDL+ — status and tooling

### HDDL
- **[V]** HDDL is the HTN extension of PDDL (Höller, Behnke, Bercher, Biundo, Fiorino,
  Pellier, Alford — AAAI 2020). It is the input language of the IPC HTN tracks.
  https://arxiv.org/pdf/1911.05499 ,
  https://www.uni-ulm.de/fileadmin/website_uni_ulm/iui.inst.090/Publikationen/2020/Hoeller2020HDDL.pdf
- **[V]** IPC 2023 HTN track used "the same input language as the previous HTN IPC 2020"
  (an HDDL fragment). Six tracks: total-order and partial-order × agile/satisficing/optimal.
  Winners: PandaDealer (TO), Grounded-Linear (PO sat/agile), PANDApro lm-cut (PO optimal).
  Competitors had to submit their own plan-validation script. https://ipc2023-htn.github.io/
- **[V]** IPC 2026 (ICAPS 2026, Dublin) announced a numeric track and an epistemic track;
  I found **no** announcement of an HTN track for 2026. https://groups.google.com/g/icaps-conference/c/TZTB7Y6pYS0 ,
  https://www.icaps-conference.org/competitions/ — **[?]** absence of evidence only.
- **[V]** HDDL 2.1 (temporal HTN) is a *proposal* (arXiv 2022/2023) with a parser in PDDL4J;
  it is not what the IPC uses. https://arxiv.org/pdf/2306.07353
- **[I]** Net: HDDL (2020) is the de-facto standard for HTN interchange; it is maintained by
  the research community via IPC benchmarks, not by a standards body. Nothing is "moving"
  fast; it's stable.

### PDDL 3.1 / PDDL+
- **[V]** PDDL 3.1 (IPC 2008) is still the latest official version; IPCs since 2011 use a
  subset of it. https://ipc2023-classical.github.io/ ,
  https://ipc08.icaps-conference.org/deterministic/PddlExtension.html ,
  https://en.wikipedia.org/wiki/Planning_Domain_Definition_Language
- **[V]** PDDL+ (processes/events, hybrid) exists as an extension; VAL validates PDDL+
  plans with numeric simulation; ENHSP is a commonly used PDDL+ planner.
  https://arxiv.org/pdf/1110.2200
- **[I]** PDDL+ is irrelevant for us unless we want the planner to reason about continuous
  processes (curing, settling). Don't.

### Parsers / validators (checked via GitHub API this session)
| Tool | What | Lang | License | Last push | Notes |
|---|---|---|---|---|---|
| pandaPIparser | HDDL parser, grounder input, **plan verifier**; can emit (J)SHOP2 and HPDL | C++17 (flex/bison) | BSD-3-Clause | 2024-06 | **[V]** https://github.com/panda-planner-dev/pandaPIparser . README warns some PO orderings cannot be expressed in SHOP2 |
| HDDL-Parser (koala-planner, ANU) | HDDL LSP/validator; exports AST as **JSON** | Rust | **no license file** (GitHub API: null; not in Cargo.toml) | 2026-08 | **[V]** https://github.com/koala-planner/HDDL-Parser , ICAPS'25 demo https://icaps25.icaps-conference.org/program/demos-pdfs/ICAPS25-Demo_paper_2.pdf . Without a license you legally can't vendor it. |
| unified-planning (AIPlan4EU) | Python API; `HierarchicalProblem`, `Method`, `Task`; HDDLReader/HDDLWriter | Python | Apache-2.0 | 2026-09 (active) | **[V]** https://unified-planning.readthedocs.io/en/latest/problem_representation.html , https://unified-planning.readthedocs.io/en/latest/interoperability.html |
| PDDL4J | PDDL + HDDL (incl. 2.1 proposal) parser/planners | Java | LGPL-3.0 | 2024-09 | **[V]** https://github.com/pellierd/pddl4j |
| VAL | PDDL(2.1/+) plan validator | C++ | BSD-3-Clause | 2021-10 | **[V]** https://github.com/KCL-Planning/VAL — effectively dormant |
| `pddl` (AI-Planning) | PDDL 3.1 parser | Python | (MIT **[?]**) | 0.4.8, 2026-06 | **[V]** release dates via https://libraries.io/pypi/pddl |

---

## 2. HTN in shipped games; embeddable libraries

### Shipped games
- **[V] Guerrilla / Decima.** Tim Verweij's talk "HTN Planning in Decima" (AI and Games
  Conference 2024) says Decima's HTN planner drives NPC high-level decisions in the Horizon
  series (HZD, Forbidden West) and Killzone; backtracking "similar to Prolog" over
  preconditions; the domain is compiled to **generated C++**; in-game decomposition debugging.
  https://www.guerrilla-games.com/read/htn-planning-in-decima
- **[V] Killzone 2** multiplayer bots: HTN planner + commander/squad/individual layering (2009).
  https://www.guerrilla-games.com/read/killzone-2-multiplayer-bots
- **[V] Transformers: Fall of Cybertron** used a total-order forward-decomposition (SHOP-style)
  HTN; replaced War for Cybertron's GOAP and was faster. Troy Humphreys, *Game AI Pro* ch.12.
  https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter12_Exploring_HTN_Planners_through_Example.pdf ,
  https://www.youtube.com/watch?v=kXm467TFTcY
- **[I]** Also commonly cited: Max Payne 3, Dying Light (HTN), F.E.A.R. (GOAP). Pattern across
  all of them: **total-order forward decomposition**, designer-authored methods, replan on
  world change. None of the shipped game planners do partial-order HTN.

### Embeddable libraries
| Library | Lang | License | Status | Fit |
|---|---|---|---|---|
| Fluid HTN (ptrefall) | C# | MIT | active (push 2026-03), 454★ | **[V]** https://github.com/ptrefall/fluid-hierarchical-task-network . Total-order; builder API (domains are code); partial plans ("PausePlan"); runtime domain **slots** (splice sub-domains, e.g. smart objects); decomposition log. README: "JSON serialization of HTN Domains in the works" (i.e. not done). |
| godot-fluid-hierarchical-task-network (fnaith) | **GDScript**, Godot 4 | MIT | push 2026-03, 26★ | **[V]** https://github.com/fnaith/godot-fluid-hierarchical-task-network . Port of Fluid HTN with tests. Small user base. |
| fluid HTN C++ port (amoldeshpande) | C++ | MIT | push 2023-12, 10★ | **[V]** https://github.com/amoldeshpande/fluid-hierarchical-task-network — low activity |
| GamePlanHTN | JS | MIT | push 2022-12, 6★ | **[V]** https://github.com/TotallyGatsby/GamePlanHTN — stale |
| V-Sekai godot_hierarchical_task_network | C++17 (Pyhop→C++, TFD) | Apache-2.0 | **archived 2023-03** | **[V]** https://github.com/V-Sekai/godot_hierarchical_task_network |
| SHOP3 | Common Lisp | MPL | active (4.2, 2026-03) | **[V]** https://github.com/shop-planner/shop3 . Can emit HDDL-format plans. Not embeddable in Godot. |
| GTPyhop | Python | BSD-3-Clause-Clear | last push 2021 | **[V]** https://github.com/dananau/GTPyhop — see §4 |
| PANDA family (pandaPIengine etc.) | C++ | BSD **[?]** | research | Heavy grounding planners; wrong tool for runtime game use **[I]** |

**[I]** For us, none of these is worth adopting as-is. A total-order forward-decomposition
planner over our own IR is a few hundred lines (Pyhop's core is <150 lines of Python per the
GTPyhop paper). The value is in the *domain representation*, which is exactly the part these
libraries express as host-language code.

---

## 3. GOAP vs HTN vs behaviour trees for hierarchical construction

Use case: "completed log cabin" → clear → foundation → walls → roof → openings; ordered
structure; preconditions over world state; also a *test script* and *recording* format.

- **GOAP** (STRIPS search over flat actions, F.E.A.R.). Finds novel sequences, but: no
  hierarchy, so "log cabin" must be a goal predicate the search reaches from primitive
  actions — search blows up with many parametric placement actions (F.E.A.R. 2's reported
  scaling problems: https://gamedev.net/forums/topic/700989-fsm-bt-htn-goap-other/ **[V]**
  forum-grade source). Its plans are flat, so a recording carries no "why". **Reject.**
- **Behaviour trees.** Execution control, not planning. Great for *how the avatar performs
  one primitive* (walk there, swing axe, retry on fail). Poor as a goal language: no world
  model, no lookahead, can't validate a recording against intent. **Use below the planner,
  not instead of it.**
- **HTN.** Knowledge lives in methods ("a cabin is foundation, then walls, then roof"); the
  planner only chooses among authored methods and binds parameters. That is precisely the
  thing we want to write once and use three ways: a test scenario is a task network; a
  recording is a (partially) decomposed plan; the in-game planner decomposes the player's
  goal. **Recommend HTN.**

Specific recommendations **[I]**:
1. **Total-order forward decomposition (SHOP/Pyhop style)** for the runtime planner. One
   avatar executes actions sequentially anyway, and the state at each step is concrete,
   which makes preconditions evaluable by ordinary engine queries (SDF samples, part
   lookups). Every shipped game planner found is total-order.
2. **Allow partial order in the *authoring* language** (HDDL-style `ordering` constraints,
   or "unordered" blocks), and linearize at plan time. Partial order is how the method
   *means* ("the four walls in any order, all before the roof"); a recording that
   placed walls N,E,S,W must validate against the same method as one that placed W,S,E,N.
   That validation need is the strongest argument for partial-order in the IR.
3. **Mix goals and tasks (GTPyhop's GTN idea).** "Area cleared" is naturally a goal
   (state predicate) with methods to achieve it; "build walls" is a task. GTPyhop verifies a
   goal is actually true after its sub-plan and backtracks otherwise — that verification is
   also a free test assertion for us.
4. Keep **replan-on-failure** (Fluid HTN/Transformers pattern) rather than plan repair.

---

## 4. Non-Lisp surface syntaxes and lessons

- **[V] Pyhop / GTPyhop (Nau):** domains are plain Python. Actions are functions that
  mutate and return state or return nothing for "inapplicable"; methods are functions that
  return a **to-do list** of tasks/actions/goals computed by ordinary code (`for`/`if`).
  Stated motivation: game developers were writing their own planners rather than learn
  planning languages; a planner "easily integrated … uses data structures compatible with
  those used in the larger system … rather than requiring the data to be translated between
  two different representation schemes." Pyhop saw wide reuse (66 citing papers at the
  time) despite zero promotion. https://www.cs.umd.edu/~nau/papers/nau2021gtpyhop.pdf
- **[V] unified-planning:** Python object API (`HierarchicalProblem`, `Method`, `Task`,
  subtasks + ordering constraints), round-trips to HDDL. Declarative objects rather than
  code-as-methods. https://unified-planning.readthedocs.io/en/latest/problem_representation.html
- **[V] Fluid HTN:** C# fluent builder (`.Select(…).Sequence(…).Condition(…).Action(…)`);
  JSON serialization still "in the works" years on — **[I]** a sign that once conditions and
  effects are lambdas, serializing the domain becomes hard. This is the central lesson.
- **[V] HDDL-Parser** exports the parsed HDDL AST as JSON for other tools, i.e. the HDDL
  community itself treats JSON as the interchange shape and Lisp as the authoring shape.
- **[V] pandaPIparser** notes some partial-order methods cannot be expressed in SHOP2's
  language — translating between HTN dialects is lossy around ordering.
- **[?]** I did not find any published YAML surface syntax for HTN with a lessons-learned
  write-up. Search hits for "Godot 4.5 JSON HTN config" were unverifiable snippets.

**Lessons, synthesized [I]:**
1. *Methods-as-code* (Pyhop, Fluid) is the most pleasant to write and the least portable:
   the domain can't be serialized, diffed, validated, or executed by a different runtime.
   Our three-uses requirement (tests, recordings, in-engine planner) means the **canonical
   form must be data**, with a small, closed expression language for preconditions/params
   that GDScript and C++ can both interpret.
2. Put *arbitrary* computation behind **named, engine-implemented predicates and
   generators** (e.g. `wall_segments(wall, spacing: 0.5)`, `surface_clear(aabb)`), not inline
   code. That keeps the IR declarative while letting geometry stay in C++.
3. Ordering semantics must be explicit in the IR from day one; retrofitting partial order
   onto a total-order format is where dialect translations break.

---

## 5. CoffeeScript 2 status; CoffeeScript as internal DSL

- **[V]** Latest release is **2.7.0, 2022-04-24** (npm `time` field). `engines: node >=6`.
  Last commit on master **2023-09-19**; last CI change added Node 20 (2023-07). Repo not
  archived, 98 open issues; newest open issue 2026-02 ("unusable with Svelte 5"); issue
  #5470 (2024) asks for JSON import attributes. https://www.npmjs.com/package/coffeescript ,
  https://github.com/jashkenas/coffeescript/issues
- **[V]** Tested this session: `coffeescript@2.7.0` on **Node v26.10.0** — `coffee file`,
  `coffee -c`, and `require('coffeescript/register')` all worked for a small DSL file.
- **[I]** Characterization: *stable/unmaintained*, not *broken*. Risk is future ESM-only
  ecosystem friction and no new syntax; for a build-time tool that emits JSON/YAML this risk
  is small and contained (worst case: freeze the Node version, or port the ~few hundred
  lines of DSL to JS).

**Internal DSL feasibility [I]:** reasonable, *if* the DSL is a builder that emits the
declarative IR and never lets closures leak into it. CoffeeScript's implicit calls/objects
make it read close to YAML:

```coffee
task 'build_cabin', site: 'Area', ->
  method 'standard',
    pre: ['cleared site']
    ordered: [
      ['foundation', 'site']
      unordered: [['wall', 'site', d] for d in ['N','E','S','W']]...
      ['roof', 'site']
    ]
```
Note the `for` comprehension runs at *compile time* in node — fine for fixed structure,
wrong for anything that depends on runtime world state (that must become an IR construct,
see §6). Enforce this by making the DSL's output schema-validated JSON and failing the
build on any function value.

**How GDScript consumes it:** the node tool compiles `*.coffee` → `domain.json` (or YAML;
JSON is simpler because Godot has a built-in `JSON` parser and no built-in YAML parser —
**[I]**, Godot 4 has `JSON`, and YAML would need an addon). GDScript loads the JSON into
typed Resources at startup; C++ can read the same file if the planner moves to the module.
Recordings are written by the engine in the same IR (plan = decomposition tree + resolved
primitive actions with bound params) and turned into GUT tests by a generator (either the
node tool or GDScript). Alternative worth weighing: author directly in YAML with a JSON
Schema, and keep CoffeeScript only for generators/linters — less expressive, zero second
language. **[I]** Given the "one language" goal, a YAML IR that *is* the language, with
CoffeeScript tooling around it, is the more boring and more robust choice; the CoffeeScript
DSL earns its place only if YAML's lack of abstraction (macros, loops over literal lists)
becomes painful.

---

## 6. Parametric / repeating tasks (battlements every 0.5 m)

- **[V]** HDDL has no loop construct; repetition is expressed by **recursive methods**
  (a task with a base-case method and a recursive method), as in the unified-planning
  navigation example (a no-op method plus a recursive `go` method).
  https://unified-planning.readthedocs.io/en/latest/problem_representation.html
- **[V]** GTPyhop/Pyhop methods compute the subtask list in code, so a loop is just a `for`
  that returns N subtasks. https://www.cs.umd.edu/~nau/papers/nau2021gtpyhop.pdf
- **[I]** SHOP has `forall`/`:sort-by` and call terms in preconditions; I recall a
  `forall` in SHOP2 but have **not verified** SHOP3's loop syntax. **[?]**
- **[I]** HDDL/IPC HTN is essentially object-typed and non-numeric; metric positions like
  "0.5 m gaps" do not fit classic HDDL without discretization. **[?]** — check whether the
  IPC HDDL fragment allows numeric fluents; I believe it doesn't.

**Proposed representation [I]:**
1. **Generator-bound parameters.** A method may bind a parameter from an engine-supplied
   generator: `each seg in wall_segments(wall, pitch: 1.0, gap: 0.5)` → one subtask per
   element, ordering `unordered` or `sequential`. Generators are named, deterministic,
   implemented in C++/GDScript, and evaluated at decomposition time against the current
   state. This is SHOP-style call terms made explicit, and it keeps the recorded plan
   reproducible (the bound values are recorded).
2. **Recursion as the fallback** for state-dependent repetition ("keep clearing until
   `cleared(area)`"): base-case method with the goal as precondition + recursive method.
   GTPyhop's goal verification gives the termination/assertion check.
3. **Geometry is a parameter type, not a predicate soup.** `wall` is an object with a
   polyline; `seg` is a transform. Don't try to express "0.5 m apart" as planner
   predicates.
4. Recorded plans store the **bound** generator outputs, so a GUT test replays exact
   transforms and separately can assert the method still generates the same bindings
   (a regression gate on the generator).

---

## Bottom line [I]
- Use **HTN, total-order forward decomposition at runtime, partial order allowed in the
  authored IR**, goals+tasks mixed (GTPyhop-style), BTs only for primitive execution.
- The **canonical artifact is a declarative JSON/YAML IR** with a closed expression
  language and named engine predicates/generators; both GDScript and C++ can read it.
- Borrow HDDL's *structure and semantics* (tasks, methods, ordering, typed params,
  decomposition-tree plans); optionally write an HDDL exporter later to validate domains
  with pandaPIparser (BSD) — not HDDL-Parser, which has no license.
- CoffeeScript 2.7.0 works on Node 26 but is frozen since 2022/2023; fine as a
  build-time DSL/tooling language that emits the IR, not as the IR itself.
- No existing library fits well enough to adopt; the GDScript Fluid HTN port is the closest
  prior art to read, but its domains are code, which defeats uses (1) and (2).
