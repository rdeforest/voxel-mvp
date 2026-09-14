# Event bus: no re-entrancy guard, prunes dead subs mid-iteration

**Status:** Deferred (2026-06-22). Diagnosed by code review. Latent — reachable by design (handlers already
emit from inside handlers), but no current channel chains onto *itself*, so it hasn't bitten yet.

## Symptom (expected when it triggers)
A live subscriber is skipped for an event, or a handler fires twice, when an emit happens during dispatch
of the same channel.

## Cause
`scripts/events/voxel_event_bus.gd:88-130`. `_dispatch_channel` iterates `for sub in subs` and, when it
finds a dead weakref, does `subs.erase(sub)` (`:107`). A nested `emit` on the **same channel** (reached
while a handler runs) re-enters `_dispatch_channel`, and its dead-sub pruning mutates the same `subs` Array
the outer loop is mid-iteration over. GDScript `for` over an Array indexes by position, so erasing an
element the outer loop hasn't reached yet makes it skip the next (live) subscriber.

`_on_terrain_sdf_changed` already emits `voxel_removed` synchronously from inside a `terrain_sdf_changed`
handler (`scripts/structural/terrain_support.gd:39`), and MPM/DetachmentScout emit `terrain_sdf_changed`
from `_physics_process`. So reentrant emit is normal; it's only safe today because no handler re-emits its
*own* channel. The pruning code is simply not reentrancy-safe.

(Confirmed clean: every `subscribe`/`subscribe_cell` callback in `scripts/` is a bound method — no lambda
leaks. The WeakRef discipline holds.)

## Proposed fix
Snapshot the subscriber list before iterating (iterate `subs.duplicate()`), and defer structural mutation
(collect dead subs, prune after the loop). Standard reentrancy-safe dispatch.

## References
`scripts/events/voxel_event_bus.gd` `_dispatch_channel`/`_dispatch_cell`; emit-from-handler site
`scripts/structural/terrain_support.gd:39`.
