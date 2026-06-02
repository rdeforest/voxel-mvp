# Voxel Event Bus

*Shipped in Phase 5.5a (commit ee80b63). This spec is preserved because
the bus is a foundational architectural decision and the rationale for
its shape matters for anyone extending it.*

## Context

Phase 5.5a was the root architectural commitment for v0.1: decouple
voxel editing from systems that care about voxel changes. Before the
bus, every `*_action.gd` carried a `StructuralIntegrity` reference and
called mutation methods directly. That worked for one indexer; it
wouldn't scale to two (building registry, biome map, ore depletion,
decay, fire propagation, weather).

End state (shipped): actions emit events. `StructuralIntegrity` is a
subscriber. `player.gd` no longer holds an `integrity` ref for mutation
purposes. The bus is multi-grid-shaped from day one (every event
payload carries a `grid_id`) even though only one grid exists.

## Design locks

- **Location:** Autoload singleton `VoxelEventBusSingleton`.
- **Subscription:** Per-cell only for MVP. Method named
  `subscribe_cell(...)`, leaving `subscribe(...)` reserved for future
  region/AABB/global modes.
- **Lifetime:** `Callable.is_valid()` + lazy sweep. No WeakRef wrapping.
  Manual `unsubscribe_cell(...)` available as escape hatch.
- **Payload:** Typed event classes (RefCounted), one per channel.
- **Tiers:** Primitive events (emitted by actions) + derived events
  (emitted by integrity into the same bus).
- **Queries** (`has_part`, `has_part_cell`) stay as direct calls —
  they're synchronous validation, not notification. Actions retain a
  `PartRegistry` (or current integrity ref limited to read-only methods)
  for these.

## Event taxonomy

| Channel                 | Tier      | Payload fields                                          | Emitter                              |
| ----------------------- | --------- | ------------------------------------------------------- | ------------------------------------ |
| `terrain_sdf_changed`   | primitive | `grid_id, box_origin, box_size`                         | DigAction, FillAction, FlattenAction |
| `voxel_added`           | primitive | `grid_id, pos, material`                                | FillAction                           |
| `voxel_removed`         | primitive | `grid_id, pos`                                          | DigAction, CollapseDetector          |
| `part_added`            | primitive | `grid_id, node, cells, material, placement_y, part`     | ConstructionAction, WorldSnapshot    |
| `part_removed`          | primitive | `grid_id, node`                                         | RemovalAction                        |
| `voxel_support_changed` | derived   | `grid_id, pos, old_support, new_support`                | TerrainSupport                       |
| `part_support_changed`  | derived   | `grid_id, node, old_support, new_support`               | PartSupport                          |
| `region_collapsing`     | derived   | `grid_id, cells`                                        | CollapseDetector                     |

`register_exposed_cells` was absorbed: `TerrainSupport` subscribes to
`terrain_sdf_changed` and runs its own boundary scan. The action layer
no longer knows this is a thing.

`notify_terrain_changed` was replaced by `terrain_sdf_changed`.
Subscribers compute their own staleness from the box.

## Bus API

```gdscript
# Autoload, accessible as VoxelEventBus.

func subscribe_cell(channel: StringName, cell: Vector3i, callback: Callable) -> void
func unsubscribe_cell(channel: StringName, cell: Vector3i, callback: Callable) -> void
func emit(channel: StringName, event: RefCounted) -> void
```

Internal:
```
_subs: Dictionary[StringName, Dictionary[Vector3i, Array[Callable]]]
```

`emit` looks up `_subs[channel]`, for each cell in the event's footprint
iterates its callable list, drops invalid ones, invokes valid ones.
Footprint extraction is per-channel — a `terrain_sdf_changed` event
walks every cell in its box; a `voxel_added` walks one cell.

## Lifetime & cleanup

- Subscribers call `subscribe_cell(channel, cell, my_method)` once per
  cell.
- On `emit`, bus walks the per-cell callable list, skips
  `!callable.is_valid()` entries, and queues them for removal.
- A lazy sweep at end of emit prunes dead entries. No periodic timer
  needed; subs only die when their owner died, and we discover that
  the next time we visit their cell.
- Manual `unsubscribe_cell` is available for early cleanup (e.g., a
  part hovering visualisation that wants to stop updating before its
  Node is freed).
- Reference cycle audit: `StructuralIntegrity._exit_tree` unsubscribes
  its bus connections in addition to breaking the
  TerrainSupport ↔ PartSupport cycle. Without explicit unsubscribe,
  the autoload bus holds Callables that reference RefCounted
  components, preventing them from freeing.

## Out of scope (deferred)

- Region/AABB subscriptions (`subscribe_region`) — add when a second
  subscriber type needs them.
- Priority/ordering between subscribers — current single-subscriber-
  per-cell ordering is good enough.
- Event batching — emit one at a time for MVP.
- Cross-grid event routing — payload carries `grid_id` but dispatch is
  single-grid.
- A query bus / read-side equivalent — direct refs to a `PartRegistry`
  are fine for now.
