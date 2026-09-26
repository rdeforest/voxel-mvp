extends GutTest

# VoxelImprint.apply returns the flips it measured across its write, and they are the very cells
# its voxel_added / voxel_removed events carried: ConstructionAction registers a part in PartIndex
# from that return, so it and the events the structural sim hears must be one set.
# (Drafted by Claude, overnight 2026-09-26.)

const Store := preload("res://test/support/predict_store.gd")

var _added:   Array[Vector3i] = []
var _removed: Array[Vector3i] = []


func before_each() -> void:
    _added.clear()
    _removed.clear()
    VoxelEventBusSingleton.subscribe(VoxelAddedEvent.CHANNEL, _on_added)
    VoxelEventBusSingleton.subscribe(VoxelRemovedEvent.CHANNEL, _on_removed)

func after_each() -> void:
    VoxelEventBusSingleton.unsubscribe(VoxelAddedEvent.CHANNEL, _on_added)
    VoxelEventBusSingleton.unsubscribe(VoxelRemovedEvent.CHANNEL, _on_removed)

func _on_added(e: VoxelAddedEvent) -> void:
    _added.append(e.pos)

func _on_removed(e: VoxelRemovedEvent) -> void:
    _removed.append(e.pos)

func _sorted(cells: Array[Vector3i]) -> Array[Vector3i]:
    var out := cells.duplicate()
    out.sort()
    return out


# A turned box added across the edited surface, then a sphere carved through it: each apply's
# return equals its own events, on the game's multi-level field.
func test_apply_returns_the_flips_its_events_carried() -> void:
    var fixture := Store.new()
    var at      := Vector3(100.0, fixture.surface, 100.0)
    var turned  := Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), at + Vector3(0.4, 0.3, 0.2))

    var added := VoxelImprint.apply(fixture.store, &"Wood", CsgBoxShape.new(Vector3(4.0, 2.0, 1.5)),
        turned, CsgState.Op.ADD)
    assert_false(added.solid.is_empty(), "the box makes cells solid (else this tests nothing)")
    assert_eq(_sorted(added.solid), _sorted(_added), "ADD: returned solid == voxel_added")
    assert_eq(_sorted(added.air), _sorted(_removed), "ADD: returned air == voxel_removed")

    _added.clear()
    _removed.clear()
    var carved := VoxelImprint.apply(fixture.store, &"Stone", CsgSphereShape.new(1.8),
        Transform3D(Basis(), at + Vector3(1.0, 0.5, 0.0)), CsgState.Op.SUBTRACT)
    assert_false(carved.air.is_empty(), "the sphere empties cells (else this tests nothing)")
    assert_eq(_sorted(carved.air), _sorted(_removed), "SUBTRACT: returned air == voxel_removed")
    assert_eq(_sorted(carved.solid), _sorted(_added), "SUBTRACT: returned solid == voxel_added")
