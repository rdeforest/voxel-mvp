extends Node

# Spatial pub/sub for voxel-grid events. Subscribers register per-cell or
# channel-wide interest; the bus dispatches each emitted event to the
# subscribers whose interest overlaps the event.
#
# Lifetime: each subscription stores a WeakRef to the subscriber object plus
# the method name. When the subscriber is freed (Node.queue_free, or a
# RefCounted's last external strong reference goes away), the WeakRef goes
# null and the subscription is pruned lazily on the next emit. Callers do
# not need to unsubscribe to avoid leaks. Manual unsubscribe is available
# for the "context changed, stop listening" case.
#
# Caveat: subscribe with a bound method (`self.my_method`), not an anonymous
# lambda. Lambdas have no Object to weakref and would persist until
# explicitly removed.

class Subscription:
    extends RefCounted

    var weak_owner: WeakRef
    var method:     StringName

    func _init(callback: Callable) -> void:
        weak_owner = weakref(callback.get_object())
        method     = callback.get_method()

    func invoke(event: VoxelEvent) -> bool:
        var obj = weak_owner.get_ref()
        if obj == null:
            return false
        obj.call(method, event)
        return true

    func matches(callback: Callable) -> bool:
        return weak_owner.get_ref() == callback.get_object() \
           and method == callback.get_method()

    func dedup_key() -> String:
        var obj = weak_owner.get_ref()
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

func emit(channel: StringName, event: VoxelEvent) -> void:
    var seen: Dictionary = {}
    _dispatch_channel(channel, event, seen)
    _dispatch_cell(channel, event, seen)

func _dispatch_channel(channel: StringName, event: VoxelEvent, seen: Dictionary) -> void:
    if not _subs_channel.has(channel):
        return
    var subs: Array        = _subs_channel[channel]
    var dead: Array        = []
    for sub: Subscription in subs:
        var key := sub.dedup_key()
        if key == "":
            dead.append(sub)
            continue
        seen[key] = true
        if not sub.invoke(event):
            dead.append(sub)
    for sub in dead:
        subs.erase(sub)

func _dispatch_cell(channel: StringName, event: VoxelEvent, seen: Dictionary) -> void:
    if not _subs_cell.has(channel):
        return
    var per_cell: Dictionary = _subs_cell[channel]
    var dead:     Array      = []
    for cell in event.cells:
        if not per_cell.has(cell):
            continue
        for sub: Subscription in per_cell[cell]:
            var key := sub.dedup_key()
            if key == "":
                dead.append([cell, sub])
                continue
            if seen.has(key):
                continue
            seen[key] = true
            if not sub.invoke(event):
                dead.append([cell, sub])
    for entry in dead:
        per_cell[entry[0]].erase(entry[1])
        if per_cell[entry[0]].is_empty():
            per_cell.erase(entry[0])

func _remove_matching(subs: Array, callback: Callable) -> void:
    for sub: Subscription in subs:
        if sub.matches(callback):
            subs.erase(sub)
            return
