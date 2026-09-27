extends SceneTree

# Throwaway: what the event bus does with callables that aren't a plain bound method (a lambda, a
# .bind()'d method), for docs/roadmap/design/04-event-bus.md "Lifetime & cleanup".
# Findings in https://github.com/rdeforest/voxel-mvp/issues/12. (Drafted by Claude, overnight 2026-09-27.)

const BusScript := preload("res://scripts/events/voxel_event_bus.gd")


class Rec:
	extends RefCounted

	var got: Array = []

	func on_event(e) -> void:
		got.append(e)

	func on_bound(e, tag) -> void:
		got.append([e, tag])

	func make_lambda() -> Callable:
		return func(e): got.append(["lambda", e])


func _event() -> VoxelEvent:
	return TerrainSdfChangedEvent.new(0, EditSource.Kind.PLAYER, AABB(Vector3.ZERO, Vector3.ONE), CellFlips.new())


func _init() -> void:
	var bus = BusScript.new()
	var rec := Rec.new()
	var lam := rec.make_lambda()
	print("lambda get_object=", lam.get_object(), " get_method=", lam.get_method())
	bus.subscribe(&"a", lam)
	bus.emit(&"a", _event())
	print("lambda delivered: ", rec.got.size(), " subs left: ", bus._subs_channel[&"a"].size())

	var rec2 := Rec.new()
	var bound := rec2.on_bound.bind("T")
	print("bound get_method=", bound.get_method())
	bus.subscribe(&"b", bound)
	bus.emit(&"b", _event())
	print("bound delivered: ", rec2.got, " subs left: ", bus._subs_channel[&"b"].size())

	var free_lam := func(e): print("free lambda got ", e)
	print("free lambda get_object=", free_lam.get_object())
	bus.subscribe(&"c", free_lam)
	bus.emit(&"c", _event())
	print("free lambda subs left: ", bus._subs_channel[&"c"].size())

	var rec3 := Rec.new()
	var lam3 := rec3.make_lambda()
	bus.subscribe(&"d", lam3)
	rec3 = null
	bus.emit(&"d", _event())
	print("lambda of freed owner, subs left: ", bus._subs_channel[&"d"].size())
	bus.free()
	quit()
