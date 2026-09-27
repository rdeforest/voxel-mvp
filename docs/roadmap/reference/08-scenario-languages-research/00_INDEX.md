# Scenario languages research — Index

*Prior-art research drafted by Claude research agents, 2026-09-26, for design doc
[`22-scenario-languages`](../../design/22-scenario-languages.md). These are the raw notes, kept
unedited: each claim is tagged verified (with its source), inference, or unsure. Where a note's
recommendation disagrees with the design doc, the design doc wins. For example, these notes
suggest YAML as the canonical form; the design chose JSON.*

## Files

- [`01-htn-goal-method-languages.md`](01-htn-goal-method-languages.md) — why methods are HTN
  (not GOAP or behaviour trees), the state of HDDL/PDDL and their tooling, planners in shipped
  games, and CoffeeScript 2.7 checked on Node 26.
- [`02-parametric-assemblies.md`](02-parametric-assemblies.md) — what to borrow from USD, LDraw,
  CityEngine's CGA, OpenSCAD/build123d, IFC and voxel-game structure formats, and why no existing
  format has real parameters.
- [`03-field-captures-and-blender.md`](03-field-captures-and-blender.md) — why OpenVDB is an
  export for Blender and not our fixture format; how the EditStore tree and `fill_region` rasters
  map onto VDB grids.
- [`04-record-replay-to-tests.md`](04-record-replay-to-tests.md) — where actions are built and
  run, what nondeterminism exists, what saves miss, and lessons from command-level versus
  input-level replay.
