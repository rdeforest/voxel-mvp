# Completed: Tools/Activities UI + Limbo Console + Phantom-Voxel Fix

**Commit:** `3ebf5cf` (multi-feature commit)

## What shipped

The single biggest UI / dev-ergonomics landing in v0.1 so far. Three
threads landed together because they're entangled: the new UI surfaces
the new verbs, the console makes the new UI testable, and the
phantom-voxel fix was found while iterating with the console.

### Tools/Activities UI

- **Three top-level Tools:** None / Landscape / Construction.
- **Tab cycles tools.** 1-9 picks the activity within the active tool.
- **Per-tool activity memory** — switching to Landscape returns to
  the activity you last had in Landscape.
- **None.Probe activity** — prints SDF + tracked + support state at
  the targeted cell to the in-game console. Made for the phantom-
  strain class of bug; useful well beyond that.
- The nine verbs (Dig / Fill / Flatten / Raise / Lower / FillVoxel /
  EmptyVoxel / Construct / Demolish) now have a clear hierarchical
  home.

### Limbo Console + seven starter commands

- **Limbo Console as a git submodule, pinned v0.7.0.**
- **Backtick toggles** the console overlay.
- **Seven starter commands:**
  - `set <var> <value>` — adjust tunables at runtime (grass shader
    uniforms, brush radii, etc.).
  - `reset` — rewinds tunables to procedural defaults without
    touching save files.
  - `quiescent` — reports `is_quiescent()` and what's keeping the
    sim non-quiescent.
  - `parts` — lists all currently-placed parts with state.
  - `voxels` — counts tracked voxels and reports memory shape.
  - `tp <x> <y> <z>` — teleport.
  - `quit_game` — graceful shutdown.
- **WorldSnapshot V3** adds tunable persistence; **V4** adds
  tool_index / activity_indices. The snapshot format gracefully
  handles both.

### Phantom-voxel deregistration fix

- **The bug:** `TerrainSupport`'s `terrain_sdf_changed` handler was
  registering newly-exposed cells correctly, but not deregistering
  tracked cells whose SDF had become air. Result: phantom strain
  indicators on cells that no longer existed.
- **The fix:** the handler now drops tracked records whose SDF has
  become air, symmetric with the existing register-on-boundary code.
- **Surfaced via** the None.Probe activity during free part placement
  iteration.

## Key decisions taken

- **Tools-then-activities, not flat verb list.** Nine flat verbs would
  be unmanageable on the keyboard. Three Tools at the top level keeps
  the mental model clean.
- **Per-tool memory of last activity.** Without it, switching tools is
  punishing — you lose the activity you were using. With it, switching
  is just "what was I doing in that tool?"
- **Limbo Console as a submodule, not a fork.** Upstream is
  maintained; we pin a version and pull updates when needed. Same
  philosophy as the engine/voxel pinning.
- **`reset` rewinds without deleting saves.** The distinction matters
  — reset is for "I broke the tunables, give me defaults," not "wipe
  the world." Two very different operations.
- **Snapshot V3/V4 are forward-compatible by design.** Newer
  snapshots refuse to load in older builds (correct); older snapshots
  load with defaulted new fields (correct).

## Lessons learned

- **The Limbo Console paid for itself within hours.** The phantom-
  voxel bug was found *because* `set` and `None.Probe` together
  let me iterate without rebuilding shaders or restarting the game.
  This is a v0.0+ commitment now — every project of this scale
  deserves a runtime console.
- **The phantom-voxel bug was a symmetry violation, not a logic
  error.** The handler had the *concept* right (track cells exposed
  by SDF changes), but had only implemented half of it (register on
  becoming exposed, but not deregister on becoming hidden again).
  The fix is two lines; the *category* of the bug — symmetry
  violations between register and deregister — is worth watching for
  in other components.
- **Multi-feature commits are usually a warning sign; this one
  earned it.** The three threads (UI, Console, bug fix) couldn't
  cleanly land separately because each depended on the previous to
  be testable. Acceptable here because the entanglement was real,
  not laziness.

## Deferred

- **More Limbo Console commands** — `dump_state`, `time_scale`,
  `force_collapse`, `replay <action.json>` — will land as needs
  emerge.
- **Replay harness** (cleanup step #4) — depends on the action
  journal/replay model still being deferred from persistence work.
  → FEAT045.
- **HUD icons replacing text labels** for tools/activities — art-
  dependent. → FEAT038.
- **Crosshair mode awareness** — current crosshair is one shape;
  should reflect tool/activity. Art. → FEAT039.
