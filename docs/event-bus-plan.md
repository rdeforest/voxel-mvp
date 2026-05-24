# Voxel Event Bus — Phase 5.5a Plan

## Context

Phase 5.5a in [roadmap.md](roadmap.md) is the root architectural commitment for v0.1: decouple voxel editing from systems that care about voxel changes. Today, every `*_action.gd` carries a `StructuralIntegrity` reference and calls mutation methods directly. This works for one indexer; it won't scale to two (building registry, biome map, ore depletion, decay, fire propagation, weather).

End state: actions emit events. `StructuralIntegrity` is a subscriber. `player.gd` no longer holds an `integrity` ref for mutation purposes. The bus is multi-grid-shaped from day one (every event payload carries a `grid_id`) even though only one grid exists.

## Design Locks (from design conversation)

- **Location:** Autoload singleton `VoxelEventBus`.
- **Subscription:** Per-cell only for MVP. Method named `subscribe_cell(...)`, leaving `subscribe(...)` reserved for future region/AABB/global modes.
- **Lifetime:** `Callable.is_valid()` + lazy sweep. No WeakRef wrapping. Manual `unsubscribe_cell(...)` available as escape hatch.
- **Payload:** Typed event classes (RefCounted), one per channel.
- **Tiers:** Primitive events (emitted by actions) + derived events (emitted by integrity into the same bus).
- **Queries** (`has_part`, `has_part_cell`) stay as direct calls — they're synchronous validation, not notification. Actions retain a `PartRegistry` (or current integrity ref limited to read-only methods) for these.

## Event Taxonomy

| Channel              | Tier      | Payload fields                                                       | Emitter                          |
| -------------------- | --------- | -------------------------------------------------------------------- | -------------------------------- |
| `terrain_sdf_changed`| primitive | `grid_id, box_origin, box_size`                                      | DigAction, FillAction, FlattenAction |
| `voxel_added`        | primitive | `grid_id, pos, material`                                             | FillAction                       |
| `voxel_removed`      | primitive | `grid_id, pos`                                                       | DigAction, CollapseDetector      |
| `part_added`         | primitive | `grid_id, node, cells, material, placement_y, part`                  | ConstructionAction, WorldSnapshot |
| `part_removed`       | primitive | `grid_id, node`                                                      | RemovalAction                    |
| `voxel_support_changed` | derived | `grid_id, pos, old_support, new_support`                            | TerrainSupport                   |
| `part_support_changed`  | derived | `grid_id, node, old_support, new_support`                           | PartSupport                      |
| `region_collapsing`     | derived | `grid_id, cells`                                                     | CollapseDetector                 |

`register_exposed_cells` is absorbed: `TerrainSupport` subscribes to `terrain_sdf_changed` and runs its own boundary scan. The action layer no longer knows this is a thing.

`notify_terrain_changed` is replaced by `terrain_sdf_changed`. Subscribers compute their own staleness from the box.

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

`emit` looks up `_subs[channel]`, for each cell in the event's footprint iterates its callable list, drops invalid ones, invokes valid ones. Footprint extraction is per-channel — a `terrain_sdf_changed` event walks every cell in its box; a `voxel_added` walks one cell.

## Files

**New:**
- `scripts/events/voxel_event_bus.gd` — autoload class.
- `scripts/events/events.gd` — typed event RefCounted classes (one file; they're small).

**Modified:**
- `project.godot` — register `VoxelEventBus` autoload.
- `scripts/actions/dig_action.gd` — emit `voxel_removed` + `terrain_sdf_changed` instead of calling integrity. Drop `integrity` param.
- `scripts/actions/fill_action.gd` — emit `voxel_added` + `terrain_sdf_changed`. Drop param.
- `scripts/actions/flatten_action.gd` — emit `terrain_sdf_changed`. Drop param.
- `scripts/actions/construction_action.gd` — emit `part_added`. Keep integrity ref *for query only* (has_part_cell). Rename param to `part_registry` once we extract one; for now type-narrow.
- `scripts/actions/removal_action.gd` — emit `part_removed`. Keep integrity ref for `has_part`.
- `scripts/structural/terrain_support.gd` — subscribe to `terrain_sdf_changed`, `voxel_added`, `voxel_removed`. Emit `voxel_support_changed` (replaces existing `voxel_support_increased` signal).
- `scripts/structural/part_support.gd` — subscribe to `part_added`, `part_removed`. Emit `part_support_changed` (new) on tick.
- `scripts/collapse_detector.gd` — subscribe to `voxel_support_changed` instead of the direct signal connect. Emit `region_collapsing` + emit `voxel_removed` per cell when materializing.
- `scripts/structural_integrity.gd` — wire bus subscriptions in `_ready`. `register_voxel`/`remove_voxel`/etc. facade methods either go away or become thin shims that emit events (preference: remove, force callers to emit directly).
- `scripts/persistence/world_snapshot.gd` — emit `part_added` / `voxel_added` during apply instead of calling integrity methods. (TerrainSupport restore path stays direct — that's a load-time bulk insert, not a runtime mutation.)
- `scenes/player/action_factories.gd` — stop threading `integrity` into actions that no longer need it. ConstructionAction/RemovalAction still get it (query path).
- `scenes/player/player.gd` — keeps integrity ref only for `set_hovered_part` and `set_debug_visuals_enabled` (UI, not voxel mutation). Those stay direct.

**Removed:**
- The `voxel_support_increased` signal on TerrainSupport (replaced by bus emission).
- `StructuralIntegrity.register_voxel` / `remove_voxel` / `notify_terrain_changed` / `register_exposed_cells` facade shims (or keep as deprecated wrappers that emit — decide during impl).

## Lifetime & Cleanup

- Subscribers call `subscribe_cell(channel, cell, my_method)` once per cell.
- On `emit`, bus walks the per-cell callable list, skips `!callable.is_valid()` entries, and queues them for removal.
- A lazy sweep at end of emit prunes dead entries. No periodic timer needed; subs only die when their owner died, and we discover that the next time we visit their cell.
- Manual `unsubscribe_cell` is available for early cleanup (e.g., a part hovering visualisation that wants to stop updating before its Node is freed).
- Reference cycle audit: `StructuralIntegrity._exit_tree` should now unsubscribe its bus connections in addition to breaking the TerrainSupport ↔ PartSupport cycle. Without explicit unsubscribe, the autoload bus holds Callables that reference RefCounted components, preventing them from freeing.

## Build Sequence

1. Add `events.gd` (typed event classes) + `voxel_event_bus.gd`. Register autoload. Confirm parser clean.
2. Add a GUT test for the bus: subscribe → emit → callback fires; freed subscriber → callback skipped; manual unsubscribe → callback skipped.
3. Refactor `TerrainSupport`: subscribe to primitives, emit `voxel_support_changed`. Stop emitting `voxel_support_increased`.
4. Refactor `CollapseDetector`: subscribe to `voxel_support_changed`. Verify rewind behaviour preserved.
5. Refactor each Action one at a time, smallest first (RemovalAction → ConstructionAction → FlattenAction → FillAction → DigAction). Run the GUT suite after each.
6. Refactor `WorldSnapshot.apply` to emit instead of direct call.
7. Drop now-unused facade methods on `StructuralIntegrity`. Final parser + GUT.
8. Manual playtest: dig, fill, flatten, build, save, load — same behaviour as today.

## Verification

- `bin/godot --path . --headless --check-only --quit` passes after each step.
- `bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/` passes 8/8 (existing) + new bus tests.
- Manual smoke test: build a cantilever, watch strain colors progress, watch collapse fire — identical to pre-refactor.
- Manual smoke test: dig a cave wider than the strain threshold, watch ceiling collapse — identical to pre-refactor.
- Save/load round-trip preserves state, including post-refactor.

## Out of Scope (Deferred)

- Region/AABB subscriptions (`subscribe_region`) — add when a second subscriber type needs them.
- Priority/ordering between subscribers — current single-subscriber-per-cell ordering is good enough.
- Event batching — emit one at a time for MVP.
- Cross-grid event routing — payload carries `grid_id` but dispatch is single-grid.
- A query bus / read-side equivalent — direct refs to a `PartRegistry` are fine for now.
