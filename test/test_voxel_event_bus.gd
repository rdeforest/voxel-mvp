extends GutTest

const BusScript = preload("res://scripts/events/voxel_event_bus.gd")

# The bus is event-agnostic: these tests drive it with their own channels and a bare event, so they
# pin its dispatch rules independently of any game event's payload.
const CHANNEL := &"test_channel"
const OTHER   := &"test_other"

class CellsEvent:
    extends VoxelEvent

    func _init(p_cells: Array[Vector3i]) -> void:
        cells = p_cells

    static func at(cell: Vector3i) -> CellsEvent:
        return CellsEvent.new([cell] as Array[Vector3i])

class Recorder:
    extends RefCounted

    var received: Array[VoxelEvent] = []

    func on_event(event: VoxelEvent) -> void:
        received.append(event)


# Runs its hook once, on the first event, so each test stages one
# mid-dispatch mutation of the bus and then watches delivery. The hook is
# dropped before it runs: a hook that captures its own Actor would otherwise
# be a reference cycle.
class Actor:
    extends Recorder

    var on_first: Callable

    func on_event(event: VoxelEvent) -> void:
        received.append(event)
        if not on_first.is_valid():
            return

        var hook := on_first
        on_first = Callable()
        hook.call()


class Holder:
    extends RefCounted

    var victim: Recorder


# Logs into an Array the test keeps, so its deliveries stay checkable after
# it has been freed.
class Witness:
    extends Recorder

    var log: Array

    func _init(p_log: Array) -> void:
        log = p_log

    func on_event(event: VoxelEvent) -> void:
        log.append(event)


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
        bus.subscribe_cell(CHANNEL, Vector3i(1, 2, 3), rec.on_event)
        bus.emit(CHANNEL, CellsEvent.at(Vector3i(1, 2, 3)))
        assert_eq(rec.received.size(), 1)

    func test_subscriber_ignores_unmatched_cell():
        bus.subscribe_cell(CHANNEL, Vector3i(1, 2, 3), rec.on_event)
        bus.emit(CHANNEL, CellsEvent.at(Vector3i(9, 9, 9)))
        assert_eq(rec.received.size(), 0)

    func test_subscriber_ignores_other_channels():
        bus.subscribe_cell(CHANNEL, Vector3i(0, 0, 0), rec.on_event)
        bus.emit(OTHER, CellsEvent.at(Vector3i(0, 0, 0)))
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
        bus.subscribe_cell(CHANNEL, Vector3i(0, 0, 0), rec.on_event)
        bus.subscribe_cell(CHANNEL, Vector3i(1, 0, 0), rec.on_event)
        bus.emit(CHANNEL,
                 CellsEvent.new([Vector3i(0, 0, 0), Vector3i(1, 0, 0)] as Array[Vector3i]))
        assert_eq(rec.received.size(), 1)

    func test_two_subscribers_each_called_once():
        var a := Recorder.new()
        var b := Recorder.new()
        bus.subscribe_cell(CHANNEL, Vector3i(0, 0, 0), a.on_event)
        bus.subscribe_cell(CHANNEL, Vector3i(1, 0, 0), b.on_event)
        bus.emit(CHANNEL,
                 CellsEvent.new([Vector3i(0, 0, 0), Vector3i(1, 0, 0)] as Array[Vector3i]))
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
        bus.subscribe_cell(CHANNEL, Vector3i.ZERO, rec.on_event)
        rec = null  # last strong ref; RefCounted frees, callable goes invalid
        bus.emit(CHANNEL, CellsEvent.at(Vector3i.ZERO))
        # No crash, no assertion failure — surviving the emit is the test.
        assert_true(true)

    func test_manual_unsubscribe_silences_callback():
        var rec := Recorder.new()
        bus.subscribe_cell(CHANNEL, Vector3i.ZERO, rec.on_event)
        bus.unsubscribe_cell(CHANNEL, Vector3i.ZERO, rec.on_event)
        bus.emit(CHANNEL, CellsEvent.at(Vector3i.ZERO))
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
        bus.subscribe(CHANNEL, rec.on_event)
        bus.emit(CHANNEL, CellsEvent.at(Vector3i(1, 2, 3)))
        bus.emit(CHANNEL, CellsEvent.at(Vector3i(9, 9, 9)))
        assert_eq(rec.received.size(), 2)

    func test_channel_subscriber_not_called_twice_when_also_cell_subscribed():
        var rec := Recorder.new()
        bus.subscribe(CHANNEL, rec.on_event)
        bus.subscribe_cell(CHANNEL, Vector3i.ZERO, rec.on_event)
        bus.emit(CHANNEL, CellsEvent.at(Vector3i.ZERO))
        assert_eq(rec.received.size(), 1)

    func test_channel_unsubscribe_silences():
        var rec := Recorder.new()
        bus.subscribe(CHANNEL, rec.on_event)
        bus.unsubscribe(CHANNEL, rec.on_event)
        bus.emit(CHANNEL, CellsEvent.at(Vector3i.ZERO))
        assert_eq(rec.received.size(), 0)

    func test_refcounted_subscriber_auto_cleans():
        # Drop the last external strong reference to a channel-wide
        # subscriber. The bus holds only a WeakRef, so the RefCounted is
        # freed and the subscription gets pruned lazily on next emit.
        var rec = Recorder.new()
        bus.subscribe(CHANNEL, rec.on_event)
        rec = null
        bus.emit(CHANNEL, CellsEvent.at(Vector3i.ZERO))
        assert_eq(bus._subs_channel[CHANNEL].size(), 0)
        # A second emit must not crash on the empty (already-pruned) list.
        bus.emit(CHANNEL, CellsEvent.at(Vector3i.ZERO))
        assert_true(true)


# docs/roadmap/design/04-event-bus.md: emit is synchronous, so a handler's
# nested emit is dispatched in full before the outer dispatch resumes.
class TestReentrancy:
    extends GutTest

    const CELL := Vector3i(4, 5, 6)

    var bus
    var outer: VoxelEvent
    var inner: VoxelEvent

    func before_each() -> void:
        bus   = BusScript.new()
        outer = CellsEvent.at(CELL)
        inner = CellsEvent.at(CELL)

    func after_each() -> void:
        bus.free()

    func _emit_inner() -> void:
        bus.emit(CHANNEL, inner)

    func _subscribe_stale(by_cell: bool) -> void:
        var stale := Recorder.new()
        _subscribe(stale, by_cell)

    func _subscribe(rec: Recorder, by_cell: bool) -> void:
        if by_cell:
            bus.subscribe_cell(CHANNEL, CELL, rec.on_event)
        else:
            bus.subscribe(CHANNEL, rec.on_event)

    func _assert_reentrant_emit_reaches_tail(by_cell: bool) -> void:
        _subscribe_stale(by_cell)
        var emitter := Actor.new()
        var tail    := Recorder.new()
        emitter.on_first = _emit_inner
        _subscribe(emitter, by_cell)
        _subscribe(tail, by_cell)

        bus.emit(CHANNEL, outer)

        assert_eq(emitter.received, [outer, inner] as Array[VoxelEvent])
        assert_eq(tail.received,    [inner, outer] as Array[VoxelEvent])

    func test_same_channel_emit_during_dispatch_reaches_every_subscriber():
        _assert_reentrant_emit_reaches_tail(false)

    func test_same_cell_emit_during_dispatch_reaches_every_subscriber():
        _assert_reentrant_emit_reaches_tail(true)

    func _live_count(by_cell: bool) -> int:
        if by_cell:
            return bus._subs_cell[CHANNEL][CELL].size()
        return bus._subs_channel[CHANNEL].size()

    func _assert_freed_after_its_turn(by_cell: bool) -> void:
        var holder := Holder.new()
        var killer := Actor.new()
        var tail   := Recorder.new()
        holder.victim   = Recorder.new()
        killer.on_first = func():
            holder.victim = null
            _emit_inner()
        var victim_ref: WeakRef = weakref(holder.victim)
        _subscribe(holder.victim, by_cell)
        _subscribe(killer, by_cell)
        _subscribe(tail, by_cell)

        bus.emit(CHANNEL, outer)

        assert_null(victim_ref.get_ref())
        assert_eq(killer.received, [outer, inner] as Array[VoxelEvent])
        assert_eq(tail.received,   [inner, outer] as Array[VoxelEvent])
        assert_eq(_live_count(by_cell), 2)

    func _assert_freed_before_its_turn(by_cell: bool) -> void:
        var holder     := Holder.new()
        var killer     := Actor.new()
        var tail       := Recorder.new()
        var victim_log := []
        holder.victim   = Witness.new(victim_log)
        killer.on_first = func(): holder.victim = null
        var victim_ref: WeakRef = weakref(holder.victim)
        _subscribe(killer, by_cell)
        _subscribe(holder.victim, by_cell)
        _subscribe(tail, by_cell)

        bus.emit(CHANNEL, outer)

        assert_null(victim_ref.get_ref())
        assert_eq(victim_log.size(), 0)
        assert_eq(tail.received, [outer] as Array[VoxelEvent])
        assert_eq(_live_count(by_cell), 2)

    func test_subscriber_freed_during_dispatch():
        _assert_freed_after_its_turn(false)

    func test_cell_subscriber_freed_during_dispatch():
        _assert_freed_after_its_turn(true)

    func test_subscriber_freed_before_its_turn_is_skipped():
        _assert_freed_before_its_turn(false)

    func test_cell_subscriber_freed_before_its_turn_is_skipped():
        _assert_freed_before_its_turn(true)

    func test_unsubscribe_of_an_earlier_subscriber_during_dispatch():
        var early    := Recorder.new()
        var remover  := Actor.new()
        var tail     := Recorder.new()
        remover.on_first = func(): bus.unsubscribe(CHANNEL, early.on_event)
        _subscribe(early, false)
        _subscribe(remover, false)
        _subscribe(tail, false)

        bus.emit(CHANNEL, outer)

        assert_eq(early.received, [outer] as Array[VoxelEvent])
        assert_eq(tail.received,  [outer] as Array[VoxelEvent])

    func test_unsubscribe_of_a_later_cell_subscriber_during_dispatch():
        var remover := Actor.new()
        var later   := Recorder.new()
        remover.on_first = func(): bus.unsubscribe_cell(CHANNEL, CELL, later.on_event)
        _subscribe(remover, true)
        _subscribe(later, true)

        bus.emit(CHANNEL, outer)

        assert_eq(later.received.size(), 0)

    func test_subscribe_during_dispatch_hears_only_later_events():
        var adder := Actor.new()
        var late  := Recorder.new()
        adder.on_first = func(): _subscribe(late, false)
        _subscribe(adder, false)

        bus.emit(CHANNEL, outer)
        bus.emit(CHANNEL, inner)

        assert_eq(late.received, [inner] as Array[VoxelEvent])

    func test_subscribe_cell_on_the_in_flight_cell_hears_only_later_events():
        var adder := Actor.new()
        var late  := Recorder.new()
        adder.on_first = func(): _subscribe(late, true)
        _subscribe(adder, false)

        bus.emit(CHANNEL, outer)
        bus.emit(CHANNEL, inner)

        assert_eq(late.received, [inner] as Array[VoxelEvent])

    func test_subscribe_on_a_later_cell_of_the_event_hears_only_later_events():
        var channel := CHANNEL
        var first   := Vector3i(1, 0, 0)
        var second  := Vector3i(2, 0, 0)
        var cells: Array[Vector3i] = [first, second]
        var event_a := CellsEvent.new(cells)
        var event_b := CellsEvent.new(cells)
        var adder   := Actor.new()
        var late    := Recorder.new()
        adder.on_first = func(): bus.subscribe_cell(channel, second, late.on_event)
        bus.subscribe_cell(channel, first, adder.on_event)

        bus.emit(channel, event_a)
        bus.emit(channel, event_b)

        assert_eq(late.received, [event_b] as Array[VoxelEvent])

    func test_nested_emit_that_empties_a_cell_list():
        var quitter := Actor.new()
        _subscribe_stale(true)
        quitter.on_first = func():
            bus.unsubscribe_cell(CHANNEL, CELL, quitter.on_event)
            _emit_inner()
        _subscribe(quitter, true)

        bus.emit(CHANNEL, outer)

        assert_eq(quitter.received, [outer] as Array[VoxelEvent])
        assert_false(bus._subs_cell[CHANNEL].has(CELL))
