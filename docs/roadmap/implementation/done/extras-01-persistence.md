# Completed: Persistence — Snapshot + Stream

**Commit:** `a4b95da`

## What shipped

The save/load infrastructure that makes the v0.0 demo actually
demoable — you can quit and come back.

- Terrain SDF persists via `VoxelStreamSQLite`. Continuous (no manual
  save) — godot_voxel handles dirty-chunk flushing.
- Structural state persists via `WorldSnapshot` (gated on
  `is_quiescent()`).
- F5 saves the snapshot; F9 loads.
- Snapshot restore bypasses the propagation queue — saved support
  values are trusted because save required quiescence.
- Snapshot version check is asymmetric: newer-than-known is rejected;
  older loads with missing fields defaulted.
- V3 snapshot adds tunable persistence (Limbo Console `set` values).
- V4 snapshot adds tool_index / activity_indices.

## Key decisions taken

- **Gate saves on quiescence, not on user demand.** Without quiescence,
  the snapshot might capture mid-propagation state and the restore
  would have to re-run propagation. By requiring `is_quiescent()`, the
  snapshot captures *settled* state; restore just trusts the numbers.
- **Asymmetric version handling.** Newer files refuse to load (don't
  silently drop fields the older code doesn't understand); older
  files load with sensible defaults. This is the right asymmetry for
  forward compatibility.
- **Continuous SDF persistence via SQLite.** No manual save for
  terrain edits — they're written through as you make them. Snapshot
  is only for the non-godot_voxel state (parts, support values,
  tunables, UI state).

## Lessons learned

- **Two saves, one consistency model.** SDF and structural state save
  through different mechanisms (SQLite stream vs. snapshot file), but
  they're consistent at load time because the snapshot can only be
  taken when nothing is propagating. The two-pipe design feels weird
  initially but is right.
- **Action-journal/replay would be a better long-term answer, but
  snapshot-on-quiescence is fine for v0.0.** The action journal is
  deferred — it's the same primitive the network layer will need (see
  [network architecture](../../design/05-network-architecture.md)).
  Building it now would be speculative; building it then is necessary.

## Deferred

- **Action-journal/replay model** — deferred. Becomes the foundation
  of network sync work in v0.9.
- **Cloud sync** — Steam handles this at v1.0.
- **Multiple save slots** — single-slot is fine for v0.0; revisit for
  v0.5 playtester drop.
