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
- **Subscription:** per-cell (`subscribe_cell(...)`) and channel-wide
  (`subscribe(...)`). Region/AABB modes are still deferred.
- **Lifetime:** the bus holds each subscriber weakly (a WeakRef plus the
  method name) and sweeps dead entries lazily on emit. Manual
  `unsubscribe_cell(...)` / `unsubscribe(...)` for early cleanup. See
  *Lifetime & cleanup*.
- **Payload:** Typed event classes (RefCounted), one per channel.
- **Tiers:** Primitive events (emitted by actions) + derived events
  (emitted by integrity into the same bus).
- **Queries** (`has_part`, `has_part_cell`) stay as direct calls —
  they're synchronous validation, not notification. Actions retain a
  `PartRegistry` (or current integrity ref limited to read-only methods)
  for these.

## Event taxonomy

*The table is the 5.5a design. What ships since 2026-09-27 is under "Matter changed" below (drafted
by Claude).*

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

### Matter changed (2026-09-27)

Every write to the store emits exactly one `terrain_sdf_changed`
(`TerrainSdfChangedEvent`), whoever made it: every Action, the MPM thaw
and the MPM freeze. Its payload:

- `source`: an `EditSource.Kind`: `PLAYER`, `INSTRUMENT` (console and
  debug writes), `MPM` (the freeze), `SCOUT` (a detachment thaw) or
  `REPLAY`. Actions take it from their `ActionContext`.
- `box_origin`, `box_size`: the rewritten box, for re-meshing and
  re-scanning. The dispatch footprint (`cells`) is every cell in it.
- `flips`: the `CellFlips` the write measured, cells that went solid and
  cells that went air (with what they were made of).

`voxel_added` and `voxel_removed` were folded into it. One write is one
fact, so subscribers can't see its cells and its box out of order, and
there's no per-cell event storm. Raise, Lower and Flatten no longer
differ from the other writers, and a subscriber tells writers apart by
the source they report, not by guessing from world state. The box
footprint lets a per-cell subscriber resting on the ground (Robert's fence
on a hill) hear a change that moved the surface under it without flipping
a cell. The class keeps its old name because `scripts/dc` subscribes by
it; the rename goes with the terrain→matter rename.

Subscribers: `TerrainSupport` (tracks the flips, scans the box),
`PartIndex` (releases the air flips, from any source), `DetachmentScout`
(seeds from the box; for its own `SCOUT` thaw only from the flips outside
the component it thawed; ignores `MPM`: [#20](https://github.com/rdeforest/voxel-mvp/issues/20) (`scout-ignores-freeze-flips`)), and the
DC render and collision (the box). A chunked freeze gives each chunk's event
the flips inside its box, announced frames after the write
([#14](https://github.com/rdeforest/voxel-mvp/issues/14) (`mpm-chunked-freeze-flips-arrive-late`)).

## Bus API

```gdscript
# Autoload VoxelEventBusSingleton (class VoxelEventBusType,
# scripts/events/voxel_event_bus.gd).

func subscribe_cell(channel: StringName, cell: Vector3i, callback: Callable) -> void
func unsubscribe_cell(channel: StringName, cell: Vector3i, callback: Callable) -> void
func subscribe(channel: StringName, callback: Callable) -> void
func unsubscribe(channel: StringName, callback: Callable) -> void
func emit(channel: StringName, event: VoxelEvent) -> void
```

Internal:
```
_subs_cell:    Dictionary[StringName, Dictionary[Vector3i, Array[Subscription]]]
_subs_channel: Dictionary[StringName, Array[Subscription]]
```

`emit` dispatches to the channel-wide list, then to the per-cell lists
of every cell in `event.cells`. A subscriber (object + method) hears an
event once, however many of its lists the event reaches.

## Lifetime & cleanup

*Rewritten 2026-09-27 to match the shipped bus, drafted by Claude. The
original design (`Callable.is_valid()` and an explicit unsubscribe in
`StructuralIntegrity._exit_tree`) was never what shipped: the bus has
held WeakRefs since `ee80b63`. Git has the old text.*

- Each subscription stores a WeakRef to the callback's object and the
  method's name, never the `Callable`. The autoload bus therefore holds
  no strong reference to any subscriber and can't keep one alive or
  close a reference cycle. Subscribers don't unsubscribe to avoid
  leaks, and nothing in the game does (`StructuralIntegrity` has no
  `_exit_tree`).
- A subscriber dies when its object does: a Node freed, or a
  RefCounted's last strong reference dropped. The WeakRef then returns
  null, the next emit that reaches the subscription skips it, and
  prunes it from the live list after dispatch. No timer; a dead
  subscription on a cell or channel that never emits again just stays
  in its list.
- `unsubscribe_cell` / `unsubscribe` remove the first matching
  subscription (same object and method) and cancel it, so an emit
  already in flight doesn't deliver to it either (see *Re-entrancy*).
  Use them for "stop listening" while the subscriber lives on.
- Subscribe with a plain method of an object. The bus keeps only the
  object and method name, so a lambda's method can't be found and a
  `.bind()`ed callable loses its bound arguments: either fails at its
  first delivery with a script error. That behaviour is not designed; it
  is an open bug ([#12](https://github.com/rdeforest/voxel-mvp/issues/12) (`event-bus-lambda-and-bound-callables`)).

Pinned by `test/test_voxel_event_bus.gd` (freed subscribers skipped and
pruned, RefCounted auto-clean, unsubscribe silences, and the freed and
removed mid-dispatch cases).

## Re-entrancy

*Added 2026-09-26, drafted by Claude.*

Handlers emit from inside handlers by design (TerrainSupport emits
`voxel_removed` while handling `terrain_sdf_changed`), and emit is
synchronous, so a nested emit is dispatched in full before the outer
dispatch resumes. That holds for the same channel too. On entry, before any
handler runs, `emit` snapshots the channel-wide list and the per-cell list
of every cell in `event.cells`; it dispatches from those snapshots and
prunes dead subscriptions from the live lists afterwards. So nothing a
handler does to the lists (nested emit, subscribe, unsubscribe, freeing a
subscriber) can make the outer dispatch skip or repeat a subscriber. A
subscription added mid-dispatch, on any list, first hears the next emit;
one removed mid-dispatch hears nothing more, including the rest of the
event in flight; one whose owner is freed mid-dispatch is skipped and
pruned. A handler that
re-emits its own channel unconditionally recurses without bound: the bus
does not guard against that.

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
