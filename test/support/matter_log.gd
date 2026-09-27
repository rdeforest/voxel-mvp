extends RefCounted

# Records every matter-changed event (TerrainSdfChangedEvent) on the live bus while it is alive: the
# flips each carried, in order, and the event itself. The bus holds its subscribers weakly, so a
# test keeps this in a variable for as long as it listens.
# (Drafted by Claude, overnight 2026-09-27.)

var events: Array[TerrainSdfChangedEvent] = []
var solid:  Array[Vector3i]                = []   # every event's solid flips, concatenated
var air:    Array[Vector3i]                = []   # every event's air flips, concatenated


func _init() -> void:
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_matter_changed)


func clear() -> void:
    events.clear()
    solid.clear()
    air.clear()


func sources() -> Array[EditSource.Kind]:
    var out: Array[EditSource.Kind] = []
    for event in events:
        out.append(event.source)
    return out


func _on_matter_changed(event: TerrainSdfChangedEvent) -> void:
    events.append(event)
    solid.append_array(event.flips.solid)
    air.append_array(event.flips.air)
