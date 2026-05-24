extends GutTest

const BusScript = preload("res://scripts/events/voxel_event_bus.gd")

class Recorder:
    extends RefCounted

    var received: Array[VoxelEvent] = []

    func on_event(event: VoxelEvent) -> void:
        received.append(event)


class TestSubscribeEmit:
    extends GutTest

    var bus
    var rec

    func before_each() -> void:
        bus = BusScript.new()
        rec = Recorder.new()

    func after_each() -> void:
        bus.free()

    func test_subscriber_receives_matching_cell():
        bus.subscribe_cell(VoxelAddedEvent.CHANNEL, Vector3i(1, 2, 3), rec.on_event)
        bus.emit(VoxelAddedEvent.CHANNEL, VoxelAddedEvent.new(0, Vector3i(1, 2, 3), Materials.STONE))
        assert_eq(rec.received.size(), 1)

    func test_subscriber_ignores_unmatched_cell():
        bus.subscribe_cell(VoxelAddedEvent.CHANNEL, Vector3i(1, 2, 3), rec.on_event)
        bus.emit(VoxelAddedEvent.CHANNEL, VoxelAddedEvent.new(0, Vector3i(9, 9, 9), Materials.STONE))
        assert_eq(rec.received.size(), 0)

    func test_subscriber_ignores_other_channels():
        bus.subscribe_cell(VoxelAddedEvent.CHANNEL, Vector3i(0, 0, 0), rec.on_event)
        bus.emit(VoxelRemovedEvent.CHANNEL, VoxelRemovedEvent.new(0, Vector3i(0, 0, 0)))
        assert_eq(rec.received.size(), 0)


class TestMultiCellDispatch:
    extends GutTest

    var bus

    func before_each() -> void:
        bus = BusScript.new()

    func after_each() -> void:
        bus.free()

    func test_subscriber_called_once_for_multi_cell_event():
        var rec := Recorder.new()
        bus.subscribe_cell(TerrainSdfChangedEvent.CHANNEL, Vector3i(0, 0, 0), rec.on_event)
        bus.subscribe_cell(TerrainSdfChangedEvent.CHANNEL, Vector3i(1, 0, 0), rec.on_event)
        bus.emit(TerrainSdfChangedEvent.CHANNEL,
                 TerrainSdfChangedEvent.new(0, Vector3.ZERO, Vector3(2, 1, 1)))
        assert_eq(rec.received.size(), 1)

    func test_two_subscribers_each_called_once():
        var a := Recorder.new()
        var b := Recorder.new()
        bus.subscribe_cell(TerrainSdfChangedEvent.CHANNEL, Vector3i(0, 0, 0), a.on_event)
        bus.subscribe_cell(TerrainSdfChangedEvent.CHANNEL, Vector3i(1, 0, 0), b.on_event)
        bus.emit(TerrainSdfChangedEvent.CHANNEL,
                 TerrainSdfChangedEvent.new(0, Vector3.ZERO, Vector3(2, 1, 1)))
        assert_eq(a.received.size(), 1)
        assert_eq(b.received.size(), 1)


class TestLifetime:
    extends GutTest

    var bus

    func before_each() -> void:
        bus = BusScript.new()

    func after_each() -> void:
        bus.free()

    func test_freed_subscriber_is_skipped():
        var rec = Recorder.new()
        bus.subscribe_cell(VoxelAddedEvent.CHANNEL, Vector3i.ZERO, rec.on_event)
        rec = null  # last strong ref; RefCounted frees, callable goes invalid
        bus.emit(VoxelAddedEvent.CHANNEL, VoxelAddedEvent.new(0, Vector3i.ZERO, Materials.STONE))
        # No crash, no assertion failure — surviving the emit is the test.
        assert_true(true)

    func test_manual_unsubscribe_silences_callback():
        var rec := Recorder.new()
        bus.subscribe_cell(VoxelAddedEvent.CHANNEL, Vector3i.ZERO, rec.on_event)
        bus.unsubscribe_cell(VoxelAddedEvent.CHANNEL, Vector3i.ZERO, rec.on_event)
        bus.emit(VoxelAddedEvent.CHANNEL, VoxelAddedEvent.new(0, Vector3i.ZERO, Materials.STONE))
        assert_eq(rec.received.size(), 0)


class TestChannelWideSubscribe:
    extends GutTest

    var bus

    func before_each() -> void:
        bus = BusScript.new()

    func after_each() -> void:
        bus.free()

    func test_channel_subscriber_receives_all_events():
        var rec := Recorder.new()
        bus.subscribe(VoxelAddedEvent.CHANNEL, rec.on_event)
        bus.emit(VoxelAddedEvent.CHANNEL, VoxelAddedEvent.new(0, Vector3i(1, 2, 3), Materials.STONE))
        bus.emit(VoxelAddedEvent.CHANNEL, VoxelAddedEvent.new(0, Vector3i(9, 9, 9), Materials.DIRT))
        assert_eq(rec.received.size(), 2)

    func test_channel_subscriber_not_called_twice_when_also_cell_subscribed():
        var rec := Recorder.new()
        bus.subscribe(VoxelAddedEvent.CHANNEL, rec.on_event)
        bus.subscribe_cell(VoxelAddedEvent.CHANNEL, Vector3i.ZERO, rec.on_event)
        bus.emit(VoxelAddedEvent.CHANNEL, VoxelAddedEvent.new(0, Vector3i.ZERO, Materials.STONE))
        assert_eq(rec.received.size(), 1)

    func test_channel_unsubscribe_silences():
        var rec := Recorder.new()
        bus.subscribe(VoxelAddedEvent.CHANNEL, rec.on_event)
        bus.unsubscribe(VoxelAddedEvent.CHANNEL, rec.on_event)
        bus.emit(VoxelAddedEvent.CHANNEL, VoxelAddedEvent.new(0, Vector3i.ZERO, Materials.STONE))
        assert_eq(rec.received.size(), 0)

    func test_refcounted_subscriber_auto_cleans():
        # Drop the last external strong reference to a channel-wide
        # subscriber. The bus holds only a WeakRef, so the RefCounted is
        # freed and the subscription gets pruned lazily on next emit.
        var rec = Recorder.new()
        bus.subscribe(VoxelAddedEvent.CHANNEL, rec.on_event)
        rec = null
        bus.emit(VoxelAddedEvent.CHANNEL, VoxelAddedEvent.new(0, Vector3i.ZERO, Materials.STONE))
        assert_eq(bus._subs_channel[VoxelAddedEvent.CHANNEL].size(), 0)
        # A second emit must not crash on the empty (already-pruned) list.
        bus.emit(VoxelAddedEvent.CHANNEL, VoxelAddedEvent.new(0, Vector3i.ZERO, Materials.STONE))
        assert_true(true)
