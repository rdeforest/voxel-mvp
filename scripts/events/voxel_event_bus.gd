class_name VoxelEventBusType
extends Node

# Spatial pub/sub for voxel-grid events. Subscribers register per-cell or
# channel-wide interest; the bus dispatches each emitted event to the
# subscribers whose interest overlaps the event.
#
# Runtime usage: `VoxelEventBusSingleton.subscribe(...)` — that's the
# autoload-registered instance (see project.godot). The class itself is
# named VoxelEventBusType so GDScript LSP recognises it as a global
# identifier without colliding with the autoload's singleton name.
# Godot 4 forbids a class_name from matching any autoload name.
#
# Lifetime: each subscription stores a WeakRef to the subscriber object plus
# the method name. When the subscriber is freed (Node.queue_free, or a
# RefCounted's last external strong reference goes away), the WeakRef goes
# null and the subscription is pruned lazily on the next emit. Callers do
# not need to unsubscribe to avoid leaks. Manual unsubscribe is available
# for the "context changed, stop listening" case.
#
# Caveat: subscribe with a plain method of an object (`self.my_method`), not a
# lambda or a `.bind()`ed callable. A subscription keeps only the object and
# the method name, so a lambda's method can't be found and bound arguments are
# lost: either fails at its first delivery
# (https://github.com/rdeforest/voxel-mvp/issues/12).
#
# Re-entrancy: handlers may emit, subscribe and unsubscribe mid-dispatch, on
# any channel. Semantics in docs/roadmap/design/04-event-bus.md.

class Subscription:
    extends RefCounted

    var weak_owner: WeakRef
    var method:     StringName
    var cancelled:  bool = false

    func _init(callback: Callable) -> void:
        weak_owner = weakref(callback.get_object())
        method     = callback.get_method()

    func target() -> Object:
        if cancelled:
            return null
        return weak_owner.get_ref()

    func invoke(event: VoxelEvent) -> bool:
        var obj := target()
        if obj == null:
            return false
        obj.call(method, event)
        return true

    func matches(callback: Callable) -> bool:
        return target() == callback.get_object() \
           and method == callback.get_method()

    func dedup_key() -> String:
        var obj := target()
        if obj == null:
            return ""
        return "%d:%s" % [obj.get_instance_id(), method]


# channel -> (cell -> Array[Subscription])
var _subs_cell: Dictionary = {}

# channel -> Array[Subscription]
var _subs_channel: Dictionary = {}


func subscribe_cell(channel: StringName, cell: Vector3i, callback: Callable) -> void:
    if not _subs_cell.has(channel):
        _subs_cell[channel] = {}
    var per_cell: Dictionary = _subs_cell[channel]
    if not per_cell.has(cell):
        per_cell[cell] = []
    per_cell[cell].append(Subscription.new(callback))

func unsubscribe_cell(channel: StringName, cell: Vector3i, callback: Callable) -> void:
    if not _subs_cell.has(channel):
        return
    var per_cell: Dictionary = _subs_cell[channel]
    if not per_cell.has(cell):
        return
    _remove_matching(per_cell[cell], callback)
    if per_cell[cell].is_empty():
        per_cell.erase(cell)

func subscribe(channel: StringName, callback: Callable) -> void:
    if not _subs_channel.has(channel):
        _subs_channel[channel] = []
    _subs_channel[channel].append(Subscription.new(callback))

func unsubscribe(channel: StringName, callback: Callable) -> void:
    if not _subs_channel.has(channel):
        return
    _remove_matching(_subs_channel[channel], callback)

# Every list the event can reach is snapshotted before any handler runs, so
# nothing a handler subscribes mid-dispatch hears the event in flight.
func emit(channel: StringName, event: VoxelEvent) -> void:
    var channel_subs := _snapshot_channel(channel)
    var cell_subs    := _snapshot_cells(channel, event)
    var seen:        Dictionary = {}

    _dispatch_channel(channel, channel_subs, event, seen)
    _dispatch_cell(channel, cell_subs, event, seen)

func _snapshot_channel(channel: StringName) -> Array:
    if not _subs_channel.has(channel):
        return []
    return _subs_channel[channel].duplicate()

# cell -> Array[Subscription], in event.cells order.
func _snapshot_cells(channel: StringName, event: VoxelEvent) -> Dictionary:
    var snapshot: Dictionary = {}
    if not _subs_cell.has(channel):
        return snapshot

    var per_cell: Dictionary = _subs_cell[channel]
    for cell in event.cells:
        if per_cell.has(cell) and not snapshot.has(cell):
            snapshot[cell] = per_cell[cell].duplicate()

    return snapshot

func _dispatch_channel(channel: StringName, subs: Array, event: VoxelEvent,
        seen: Dictionary) -> void:
    var dead: Array = []
    for sub: Subscription in subs:
        var key := sub.dedup_key()
        if key == "":
            dead.append(sub)
            continue

        seen[key] = true
        if not sub.invoke(event):
            dead.append(sub)

    if not dead.is_empty():
        _prune(_subs_channel[channel], dead)

func _dispatch_cell(channel: StringName, snapshot: Dictionary, event: VoxelEvent,
        seen: Dictionary) -> void:
    for cell in snapshot:
        var dead: Array = []
        for sub: Subscription in snapshot[cell]:
            if not _deliver_once(sub, event, seen):
                dead.append(sub)

        _prune_cell(channel, cell, dead)

# Looks the list up again: a handler's nested emit or unsubscribe may already
# have emptied this cell's list and dropped it.
func _prune_cell(channel: StringName, cell: Vector3i, dead: Array) -> void:
    var per_cell: Dictionary = _subs_cell[channel]
    if not per_cell.has(cell):
        return

    _prune(per_cell[cell], dead)
    if per_cell[cell].is_empty():
        per_cell.erase(cell)

# False when the subscription is dead and should be pruned.
func _deliver_once(sub: Subscription, event: VoxelEvent, seen: Dictionary) -> bool:
    var key := sub.dedup_key()
    if key == "":
        return false

    if seen.has(key):
        return true

    seen[key] = true
    return sub.invoke(event)

func _prune(subs: Array, dead: Array) -> void:
    for sub in dead:
        subs.erase(sub)

func _remove_matching(subs: Array, callback: Callable) -> void:
    for idx in subs.size():
        var sub := subs[idx] as Subscription
        if sub.matches(callback):
            sub.cancelled = true
            subs.remove_at(idx)
            return
