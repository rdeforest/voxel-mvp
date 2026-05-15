# Project Status

> **Maintenance contract:** the "Resumption Brief" must reflect the current
> moment. The "Tracker" below it can drift a little. If updating this doc
> after a session takes more than ten minutes, it's too big — shrink it.

---

## Resumption Brief

*Last updated: end of strain-window + Bug 2c session*

**Where you are:** v0.0 checkpoint, in the run-up to Phase 5 proper. Phases 0
and 2 are done; the structural integrity engine and the pending-collapse
strain window (the killer-feature core of Phase 5) are done and committed.
The actual building system — prefab pieces, snap points, voxel-to-prefab
interface — is unstarted. That's Phase 5's main body and the next big block
of work.

**Pick up here, in this order:**

1. **Test Bug 2c in-engine and commit.** The march-from-below
   `_push_player_above_terrain` fix was written but not yet verified in play.
   Stand on terrain, flatten your floor out, confirm you get snapped onto
   the new surface rather than dropping through. Try it from `_edit_fill`
   too (fill *under* yourself; should push you up, not bury you).

2. **Open a fresh conversation for Phase 5 design.** The chat thread that
   produced the strain window is heavy; start clean. Phase 5 wants to *open*
   with a design pass, not code — same discipline that kept the strain
   window from sprawling. The two design notes added to Phase 5 "Key
   decisions" in the roadmap (player-position safety, fail-honest terrain
   ops) are inputs to that conversation.

**Active mental state to preserve:** Phase 5 is the thesis defense. "Buildings
grow from the same voxel data as terrain" and "unified structural integrity
for terrain and structures" are the architectural claims to pin down on
paper before code. Budget the roadmap's full 3 weeks for it; novel-behavior
work takes longer than feels right (the strain window did).

---

## Tracker

### v0.0 — Phase status

| Phase | State | Notes |
|-------|-------|-------|
| 0 — Foundation | Done | Procedural terrain, FPS controller, gravity, day/night |
| 2 — Terrain Modification | Mostly done | Dig/fill/flatten work; bugs below |
| 5 — Building System | Partial | Structural integrity + strain window done; building system unstarted |

### Bugs

| ID | State | Notes |
|----|-------|-------|
| 1 | Done | Fallen chunks not waking — fixed (`body.can_sleep = false`) |
| 2c | **Test pending** | Player fall-through after flatten — march-from-below fix written, not yet verified in-engine |
| 2a | Deferred | Flatten clears only one sheet above — cosmetic; left until building system replaces flatten |

### Done this v0.0 cycle

- Engine bring-up on both machines (Linux desktop, macOS laptop) with
  reproducible pinned config: Godot 4.6-stable (commit `89cea1439`) +
  godot_voxel `v1.6`, double-precision
- `tools/build` script — single command brings either machine to pinned
  state; idempotent; self-heals the `modules/voxel` symlink and stale
  generated files; RAM-aware `-j`
- `bin/godot` platform-dispatching wrapper
- `tools/lib.sh`, `tools/versions.env` — single source of truth for pins
- VS Code + `godot-tools` extension wired up (with one known wart: extension
  rejects the `bin/godot` wrapper, currently pointing at the real binary
  directly — see Known Limits)
- Structural integrity engine: worklist-fixpoint support propagation,
  flood-fill collapse detection, materialization as falling rigid bodies
  with greedy box merge
- Pending-collapse strain window: 3.0s countdown, support added rewinds the
  strain so 2.7s remains, cancellation when the whole component is no longer
  a fall candidate, pulsing debug visuals for straining voxels, debug
  visuals toggle
- The seed-vs-expand split in `_is_fall_candidate` — the bug that stranded
  the reddest voxels of long structures
- Bug 1 fix (fallen chunks now wake)
- Bug 2c fix written (march-from-below `_push_player_above_terrain`)

### Deferred but tracked

| Item | Where it goes | Why deferred |
|------|---------------|--------------|
| Per-material strain duration (`STRAIN_DURATION_SEC` reads from `Materials`) | v0.1 polish / material work | Flat 3.0s is fine for v0.0; the hook is a v0.1 tuning pass |
| Nature-of-change reset scaling (critical pillar buys more time than cardboard prop) | v0.1 polish | Same reasoning; flat `STRAIN_RESET_SEC = 2.7` works |
| Surface-geometry pulse (strain feedback on terrain mesh, not debug cubes) | v0.2 art / shader pass | Real shader work; not v0.0-essential |
| Material fatigue (cumulative strain history → weak points → repair tools) | v0.9 survival/combat | Only meaningful once mobs exist to exploit weak points |
| Respawn anchor system | Deferred, unscheduled | The "right" fix for fall-through; cheap edit-driven fix covers known cases |
| Continuous per-tick fall-through check | Deferred | More robust than edit-driven, but interacts oddly with intentionally-enclosed building spaces — revisit when building exists |
| Hinge-at-boundary collapse (undermined towers tip rather than lift off) | v0.1 polish | Materialization refinement; wait for real Phase-5 scenarios to tune against |
| Generic `Propagator` extraction (worklist mechanism separated from policy) | When second use case appears | Fatigue/fluid/temperature could share it; one customer isn't enough to generalize |

### Known limits (recorded, not fixed)

- **`_resume_unfinished_floods` budget starvation:** components larger than
  `DETECTION_BUDGET` (500 voxels) take multiple settled frames to fully
  detect; continuous edit streams can starve phase-1 entirely. Not a
  correctness bug, just lag. Comment in `collapse_detector.gd`. Fix is
  budget profiling, deferred to v0.1.
- **VS Code `godot-tools` rejects `bin/godot`:** the extension validates
  its editor path as a binary and chokes on a bash wrapper. Currently
  worked around by pointing it at the real binary directly, which loses
  cross-platform portability of `.vscode/settings.json`. Plausible fix:
  have `tools/build` also emit a per-machine `.vscode/settings.json`. Not
  blocking.
- **`_push_player_above_terrain` is column-based at rounded X/Z:** if the
  player straddles a voxel boundary the surface it finds could be a voxel
  off. Probably fine in practice. If you see snaps that put the player
  half-in a wall, sample a couple of columns instead of one.

### Architectural decisions worth not re-litigating

- **Track Godot stable, not master.** Pin to `4.6-stable` (`89cea1439`).
- **Double-precision godot_voxel build from day one.** The one
  non-retrofittable architectural decision in the roadmap.
- **No engine forks.** Pull upstream directly from `godotengine/godot` and
  `Zylann/godot_voxel`. Fork when there's a concrete patch to write, not
  before.
- **`godot/modules/voxel` symlink, not `custom_modules`.** godot_voxel's
  module folder must be named exactly `voxel`; `custom_modules` derives
  the name from the directory and breaks the registration symbols.
- **Worklist-fixpoint propagation is one customer, not generalized.**
  Don't extract `Propagator` until fatigue/fluid/temperature give it a
  second customer.
- **Signals (not a custom event bus) for `voxel_support_increased`.**
  Direct emitter→listener connection; bus when a third unrelated system
  needs to listen.
- **Strain timer is per-component, accumulated against physics `delta`.**
  Not wall-clock (`Time.get_ticks_msec()` would expire windows during
  pause); not a global clock (the per-component state is the right shape
  for fatigue and per-material rates later).

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
   its shape and it's worth ten more minutes fixing the shape than letting
   it grow past the point of maintenance.
