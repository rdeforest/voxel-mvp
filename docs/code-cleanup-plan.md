# Code Cleanup Plan

Proposed refactorings to bring the codebase closer to Robert's standards
(`~/.claude/wisdom/coding_standard.md`, `~/.claude/CLAUDE.md`): minimal
comments, short functions, short files, one-thing-well objects, GoF
patterns where they earn their keep, vertical alignment, data over
control flow.

The thesis demo works. None of this is a correctness fix — every item
trades current shape for clearer shape. Sequenced so each step is
reversible and the demo never breaks for a full session.

---

## What's already aligned

Worth naming, so we don't accidentally undo it:

- **Command pattern** in `scripts/actions/` is clean. `Action` base,
  `validate()` then `execute()`, parameters frozen at construction.
- **Builder pattern** in `EditMode` (`scripts/edit_mode.gd`) is exactly
  the "configure a data object with a chain of setters" shape Robert's
  examples favour.
- **Dictionary dispatch** for input in `player._key_actions` and
  `_mouse_button_actions` — the standard's preferred shape for what
  would otherwise be an `if/elif` chain.
- **Data-driven definitions.** Materials and Parts are `.tres` files;
  adding either is a file copy plus one line.
- **Vertical alignment** is consistently applied in field blocks,
  initializer lists, and the `EditMode` builder calls.
- **Observer/Signal** wiring is minimal and load-bearing
  (`voxel_support_increased`).

The shape of v0.0 isn't structurally bad — it's mostly that two files
grew faster than their natural size budget.

---

## File-size budget

Standard: ~200 lines, hard ceiling around 250. Current state:

| File                      | Lines | Verdict                          |
|---------------------------|-------|----------------------------------|
| `structural_integrity.gd` |  508  | Way over. Three classes in one.  |
| `collapse_detector.gd`    |  484  | Over. State machine + utility.   |
| `scenes/player/player.gd` |  339  | Over. Eight concerns in one.     |
| `construction_action.gd`  |  118  | OK                               |
| Everything else           | < 100 | OK                               |

The big three are where the work is.

---

## Refactorings, in recommended order

Each item lists: **What** (concrete change), **Why** (which standard),
**Risk**, **Size** (estimated diff).

### 1. Lift the inner classes and shared shapes out of `structural_integrity.gd`

**What.** Move `PartData` into `scripts/structural/part_data.gd`. Create
`scripts/structural/voxel_record.gd` to replace the `{support, material,
dirty}` dictionary records currently stored in `voxel_data`. Likewise
`scripts/structural/pending_collapse.gd` for the `{voxels, voxel_set,
strained}` dictionaries in `collapse_detector.gd`.

**Why.** Three reasons stacked:

- Typed `Dictionary[Vector3i, VoxelRecord]` gives the editor and the
  runtime real types instead of `Variant.get("support")`.
- "Strings as keys" duplication disappears — `"support"`, `"material"`,
  `"dirty"`, `"voxels"`, `"voxel_set"`, `"strained"` all become field
  accesses with one source of truth.
- Each class becomes documentation by structure. Today, to know what
  shape a `voxel_data` value has, you grep.

**Risk.** Mechanical refactor with broad reach — every `voxel_data[pos].x`
access changes. Easy to miss one; GDScript won't always catch it at
parse time. Mitigated by doing it one shape at a time.

**Size.** ~3 small new files, ~50 lines of edits across the two big
files. No semantic change.

### 2. Split `structural_integrity.gd` into three nodes

**What.** The file currently combines:

- Terrain voxel propagation (worklist fixpoint over `voxel_data`)
- Part support recomputation (sort-bottom-up over `part_registry`)
- Debug visualization (cube meshes per tracked voxel)

Split into:

- `scripts/structural/structural_integrity.gd` — thin coordinator
  (`_physics_process` orchestration, public API surface).
- `scripts/structural/terrain_support.gd` — `voxel_data`, `dirty_queue`,
  `_process_dirty_queue`, `_calculate_support`, bedrock detection, lazy
  expansion.
- `scripts/structural/part_support.gd` — `part_registry`, `_cell_to_part`,
  `_recompute_part_support`, `_calculate_part_support`,
  `_direct_part_supporter`, strain accumulation, `_collapse_part`.
- `scripts/structural/integrity_debug.gd` — debug-cube mesh management.

`StructuralIntegrity` becomes the **Facade** (GoF): the API the player
already uses (`register_voxel`, `register_part`, `get_support`, etc.)
stays unchanged, but it delegates internally. Each component does one
thing well; the facade is just a composition.

**Why.**

- "Objects doing one thing well, even if that one thing is combining
  other objects" — that's the facade.
- 508 → ~150 + ~180 + ~120 + ~60 lines, each within budget.
- The terrain/part split is already conceptually there in the code's
  section dividers (`# --- Terrain propagation ---`, `# --- Part support
  + collapse ---`). The comments are documenting structure that wants
  to be code.

**Risk.** Higher than #1 — it moves a lot of state. Best done as one
commit per extracted node, each preserving behaviour. The player only
talks to `StructuralIntegrity`, so its interface stays stable.

**Size.** ~3 new files of 100–200 lines, ~250-line reduction in
`structural_integrity.gd`. No semantic change.

### 3. Extract the greedy box merge from `collapse_detector.gd`

**What.** Move `_greedy_merge_boxes` and `_materialize_collapse`'s
RigidBody3D construction into `scripts/voxel/falling_body_factory.gd`
(or fold into `voxel_utils.gd` if it stays small). `CollapseDetector`
then calls `FallingBodyFactory.from_voxels(voxels, terrain)`.

**Why.** The greedy merge is a pure geometric utility — 62 lines that
have nothing to do with collapse semantics. It belongs next to the
other voxel utilities.

**Risk.** Very low. Pure function; no shared state.

**Size.** ~80-line move, ~5-line call-site update.

### 4. Split `collapse_detector.gd` into a state machine

**What.** The four phases (`_resume_unfinished_floods` →
`_scan_for_new_collapses` → `tick_pending` → `_materialize`) are a
**State** pattern in disguise. Make it explicit:

- `scripts/structural/collapse_states.gd` — small enum / dispatch table
  of phase functions.
- `collapse_detector.gd` shrinks to phase coordination + the
  pending-collapse lifecycle (begin / cancel / materialize).

Or alternately: keep `CollapseDetector` as today but extract the
pending-collapse lifecycle into a `PendingCollapse` class with
`begin/cancel/materialize/tick(delta)` methods. Then the detector
becomes "iterate pending collapses" and the lifecycle becomes a real
object.

**Why.** Reading `collapse_detector.gd` today requires holding the
phase-state in your head. The current file has 200 lines of comments
explaining "phase 1 does X, phase 2 does Y" — those are signs the
phases should be functions or objects, not paragraphs.

**Risk.** Medium. The phase ordering is subtle (budget exhaustion
returning false, claim-set lifetime). Tests would help; we don't have
them. Possibly defer this until v0.0.1's replay harness exists — at
that point any regression becomes a deterministic-replay failure.

**Size.** ~150-line reorganisation, possibly one new file.

### 5. Comments: aggressive pruning

**What.** Most comments in `structural_integrity.gd` and
`collapse_detector.gd` are design-rationale paragraphs. Robert's standard
treats comments as a code smell; the wisdom file calls them "code that
needs refactoring."

Three buckets:

- **Bucket A — delete.** Comments that restate what the code does
  (`# Reverse map for cell → parts.` above a typed dict whose name is
  `_cell_to_part`). Probably ~30% of current comment lines.
- **Bucket B — promote to docs.** Genuine design rationale that's
  load-bearing for future-Claude or future-Robert. Lift to
  `docs/architecture.md` (which doesn't exist yet — this would create
  it). Examples: the in_limbo paragraph, the bedrock detection
  paragraph, the optimistic-flood-on-dirty rationale.
- **Bucket C — keep inline.** One-line "this is here because of X" notes
  where the surprise is local and the rationale is short. Examples:
  `# Stable iteration order so the merger is deterministic.` Maybe ten
  of these survive.

**Why.** Robert's standard explicitly: "eliminate comments by making
code clearer." The current state is over-commented to the point where
the comments are doing the work the code structure should do.

**Risk.** Lossy if done carelessly — some of those comments are the
only record of subtle reasoning. The mitigation is bucket B: move,
don't delete.

**Size.** ~200 line reduction across the two big files. Net new
`docs/architecture.md`.

### 6. `get_support_color` and similar threshold ladders → data table

**What.** Replace:

```gdscript
if support > 0.75: return Color(0.0, 0.3, 1.0)
if support > 0.50: return Color(0.0, 0.9, 0.2)
...
```

with:

```gdscript
const SUPPORT_COLORS = [
    [0.75, Color(0.0, 0.3, 1.0)],
    [0.50, Color(0.0, 0.9, 0.2)],
    [0.30, Color(1.0, 0.9, 0.0)],
    [0.10, Color(1.0, 0.5, 0.0)],
    [0.00, Color(1.0, 0.1, 0.0)],
]
```

and walk the table. Or `for [threshold, color] in SUPPORT_COLORS`.

**Why.** Standard: "Abstract out repetition into data structures."
Adding a new threshold becomes one row, not one branch + one return.

**Risk.** Trivial.

**Size.** ~10 lines.

### 7. Player.gd split

**What.** `scenes/player/player.gd` is 339 lines and carries: movement,
camera, input dispatch, edit-mode catalog, build state, preview state,
action factories, hover detection.

Reasonable splits:

- **`scenes/player/movement.gd`** — `_physics_process`, gravity, jump,
  WASD. Maybe 40 lines.
- **`scenes/player/camera_rig.gd`** — mouse motion, head rotation,
  mouse capture. ~20 lines.
- **`scenes/player/build_state.gd`** — rotation, part index, material
  index, basis computation. Already mostly isolated; lift it out.
  ~30 lines.
- **`scenes/player/edit_mode_catalog.gd`** — the giant `_ready()`
  edit_modes builder. ~60 lines.
- **`scenes/player/action_factories.gd`** — `_make_*_action` factories.
  ~50 lines.
- **`player.gd`** keeps input dispatch and the orchestration glue.
  ~80 lines.

The non-obvious win: the `_make_*_action` factories are a **Factory
Method** family that wants a dispatch dict, the same way `_key_actions`
is. They're currently named methods because they need closures over the
player state; that's fine, but they can still be a dict.

**Why.** Standard: "Objects doing one thing well." Right now `player.gd`
is "object doing eight things adequately."

**Risk.** Medium-high. `player.gd` is touched on every input and the
inner `EditMode` lambdas close over a lot of state. Best done after #1
so we're not splitting a moving target.

**Size.** ~5 new files of 20–60 lines each, ~250-line reduction in
`player.gd`.

### 8. Sub-cell methods inside `_calculate_support` and `_calculate_part_support`

**What.** Both are 40+ line methods with explicit case discrimination
on neighbor type (untracked solid / tracked voxel / cell-with-part).
The cases want polymorphism or a dispatch table:

```gdscript
# Sketch:
const SUPPORT_SOURCES = [
    [_neighbor_is_tracked,   _support_from_tracked],
    [_neighbor_is_part_cell, _support_from_parts],
    [_neighbor_is_bedrock,   _support_from_bedrock],
    [_neighbor_is_suspended, _support_from_suspended],  # lazy-registers
]
```

then `_calculate_support` becomes a fold over neighbours through this
table.

**Why.** Standard: "Express if/else-if chains as arrays of functions."
Also collapses two parallel ~40-line functions toward a shared shape.

**Risk.** Medium. These functions are load-bearing for the thesis demo.
The case ordering matters (bedrock-below short-circuits to
FULL_SUPPORT). Worth doing after #1 lands so the data types are clear.

**Size.** ~80-line restructure.

### 9. Action factories in `player.gd` → dispatch dict

**What.** The five `_make_*_action` functions could be a dict:

```gdscript
var _action_factories := {
    "Dig":     _make_dig_action,
    "Fill":    _make_fill_action,
    "Flatten": _make_flatten_action,
    "Build":   _make_construction_action,
    "Remove":  _make_removal_action,
}
```

and then EditMode doesn't carry `make_action` at all — it just carries
a name, and the dispatch is one lookup.

**Why.** Matches the input-dispatch pattern. Removes the `.on_make_action`
slot from EditMode (one less field to wire). Subsumes into #7.

**Risk.** Low if done as part of #7.

**Size.** Small.

---

## Recommended sequence

1. **#1** (typed records) — pure mechanical, sets up everything else.
2. **#3** (extract greedy merge) — independent, low-risk warm-up.
3. **#5** (comments: bucket A delete, bucket B promote to docs) —
   reveals what's actually doing work in the big files.
4. **#2** (split structural_integrity into facade + components) — biggest
   structural win; easier after #1 and #5.
5. **#6** (color table) — trivial, anywhere.
6. **#7** + **#9** (player.gd split) — independent of the others.
7. **#8** (case dispatch in support calc) — after #1/#2 settles.
8. **#4** (collapse-detector state machine) — defer until v0.0.1
   replay harness exists, so regressions are catchable.

Each numbered item should land as its own commit, ideally with the
demo verified between commits. Total estimated diff: ~1500 lines
moved/restructured, ~300 net line reduction, no semantic change.

---

## Explicit non-goals

These would be improvements but aren't on this plan:

- **Performance work.** Threading the propagation loop, GPU offload —
  documented in roadmap.md as v0.1.
- **New tests.** Worth doing, but separate work item. The v0.0.1 replay
  harness gives us regression detection cheaper than unit tests for
  this kind of code.
- **Renaming.** Variable names like `pc`, `vt`, `mi` are GDScript-
  idiomatic and not violating the standard. Leave them.
- **Removing the `voxel_support_increased` signal** in favour of direct
  calls. The signal is the right shape — keep it.
- **Materials → singletons on a registry node instead of static class
  vars.** The current approach works and matches Parts.
- **Anything in `docs/`** — this is a code plan.

---

## Open questions for review

1. **Comments: how aggressive?** Robert's standard is clear ("eliminate"),
   but the existing comments in `collapse_detector.gd` are some of the
   best design documentation in the project. Bucket B (promote to docs)
   is the proposed compromise; happy to go further if you want.

2. **`docs/architecture.md`** — does it exist by another name, or do
   we create it as part of #5?

3. **Order of #2 (split integrity) vs #7 (split player)** — #2 is
   higher impact on file-size budget. #7 might be more cognitively
   urgent if Robert plans to add input handling soon. Either order
   works.

4. **Tests-first?** This plan doesn't add tests. The thesis demo is
   the de facto integration test. Worth pausing to add GUT coverage of
   the support propagation before #2? Probably not — v0.0.1's replay
   harness is a better foundation. But asking explicitly.
