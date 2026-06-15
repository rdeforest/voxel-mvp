# Completed: Phase 5.5a — Voxel Event Bus

Maps to [`../started/05-phase-5_5-architectural-maturation.md`](../started/05-phase-5_5-architectural-maturation.md)
section 5.5a.

**Commit:** `ee80b63`

## What shipped

The root architectural commitment for v0.1: decouple voxel editing
from systems that care about voxel changes.

- `VoxelEventBusSingleton` autoload.
- Typed event payload classes (RefCounted, one per channel).
- `subscribe_cell(channel, cell, callback)` and matching unsubscribe.
- Per-cell-only dispatch for MVP (region/AABB/global modes deferred).
- WeakRef-style lifetime via `Callable.is_valid()` with lazy sweep.
- Primitive event tier (emitted by actions): `terrain_sdf_changed`,
  `voxel_added`, `voxel_removed`, `part_added`, `part_removed`.
- Derived event tier (emitted by integrity components into the same
  bus): `voxel_support_changed`, `part_support_changed`,
  `region_collapsing`.
- Every event payload carries `grid_id` — multi-grid-shaped from day
  one even though only one grid exists. Multi-grid (Phase 5.5d)
  lands without payload churn.

## Key decisions taken

- **Subscribers register per-cell, not per-region.** Region/AABB
  subscriptions are deferred until a second subscriber type needs
  them.
- **Lifetime via `Callable.is_valid()` + lazy sweep**, not WeakRef
  wrapping. Manual `unsubscribe_cell(...)` is the escape hatch.
- **`class_name VoxelEventBusType` on the script; autoload named
  `VoxelEventBusSingleton`** — Godot 4 forbids the names from
  colliding.
- **Queries stay direct.** `has_part`, `has_part_cell`, and similar
  remain method calls — they're synchronous validation, not
  notification. Actions retain a `PartRegistry` (or limited-scope
  integrity ref) for these.
- **`register_exposed_cells` was absorbed.** `TerrainSupport`
  subscribes to `terrain_sdf_changed` and runs its own boundary scan.
  The action layer no longer knows this is a thing.
- **`notify_terrain_changed` was replaced by `terrain_sdf_changed`.**
  Subscribers compute their own staleness from the box.

## Lessons learned

- **The bus shape was the harder decision than the implementation.**
  The implementation took an afternoon; the spec took conversations.
  Once "per-cell subscriptions with WeakRef lifetime, primitive vs.
  derived event tiers" was nailed down, the code wrote itself.
- **Multi-grid from day one cost nothing.** Adding `grid_id` to every
  payload was a five-minute decision that prevents a painful refactor
  later. The payload is just a field; nothing dispatches on it yet,
  but everything is shaped to dispatch on it when needed.
- **Reference cycle audit was non-trivial.** `StructuralIntegrity._
  exit_tree` had to unsubscribe its bus connections in addition to
  breaking the TerrainSupport ↔ PartSupport cycle. Without explicit
  unsubscribe, the autoload bus held Callables that referenced
  RefCounted components, preventing them from freeing. Easy to miss;
  surfaced under leak testing.

## Deferred (with reasons)

- **Region/AABB subscriptions** — add when a second subscriber type
  needs them.
- **Priority/ordering between subscribers** — current single-
  subscriber-per-cell ordering is good enough.
- **Event batching** — emit one at a time for MVP.
- **Cross-grid event routing** — payload carries `grid_id` but
  dispatch is single-grid until Phase 5.5d.
- **A query bus / read-side equivalent** — direct refs to a
  `PartRegistry` are fine for now.

## Validation

All actions emit events; `StructuralIntegrity` subscribes; `player.gd`
no longer holds an `integrity` ref for mutation purposes. 19/19 GUT
tests pass.
