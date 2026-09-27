extends GutTest

# Part identity is the sidecar the field doesn't carry, so the save carries it beside the field: a
# reload that dropped it would leave every placed part anonymous terrain, with no record, no
# ancestry, and ids reissued from 1. The round trip is exact, since a part's transform is identity,
# not a display value.
# (Drafted by Claude, overnight 2026-09-27.)

const RunPaths  := preload("res://test/support/run_paths.gd")
const WorldStub := preload("res://test/support/world_stub.gd")

var _snapshot  := RunPaths.path("test_part_index_save.snapshot")
var _editstore := RunPaths.path("test_part_index_save.editstore")


func after_each() -> void:
    for path in [_snapshot, _editstore]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _world() -> WorldStub:
    var world := WorldStub.new()
    add_child_autofree(world)
    return world

func _store() -> EditStoreManager:
    var manager := EditStoreManager.new()
    manager.setup()
    return manager

func _place(cells: Array[Vector3i], material: StringName, xform: Transform3D, ancestry := -1,
        dimensions := Vector3(0.3, 1.7, 2.9)) -> void:
    VoxelEventBusSingleton.emit(PartPlacedEvent.CHANNEL,
        PartPlacedEvent.new(0, cells, material, dimensions, xform, ancestry))

func _carve(cell: Vector3i) -> void:
    var flips := CellFlips.new()
    flips.air = [cell]
    TerrainSdfChangedEvent.announce(EditSource.Kind.PLAYER, AABB(Vector3(cell), Vector3.ONE), flips)

# A rotation and offsets whose doubles need all 17 digits: var_to_str reads this one back an ulp off.
func _awkward_transform() -> Transform3D:
    return Transform3D(Basis(Vector3(1, 2, 3).normalized(), 0.7), Vector3(0.1, -3.3, 1.0e-7))

func _assert_same_record(got: PartRecord, want: PartRecord) -> void:
    assert_not_null(got, "part %d came back" % want.id)
    if got == null:
        return

    assert_eq(got.cells,      want.cells,      "its live cells")
    assert_eq(got.material,   want.material,   "its material")
    assert_eq(got.dimensions, want.dimensions, "its dimensions")
    assert_eq(got.transform,  want.transform,  "its transform, exactly")
    assert_eq(got.ancestry,   want.ancestry,   "its ancestry")


func test_part_index_survives_a_save_and_load() -> void:
    var source := _world()
    var beam:  Array[Vector3i] = [Vector3i(1, 2, 3), Vector3i(2, 2, 3), Vector3i(3, 2, 3)]
    var brace: Array[Vector3i] = [Vector3i(3, 3, 3)]
    _place(beam, &"Wood", _awkward_transform())
    var beam_id := source.index.part_at(beam[0])
    _place(brace, &"Stone", Transform3D.IDENTITY, beam_id, Vector3(1.1, 0.2, 0.7))
    var brace_id := source.index.part_at(brace[0])
    _carve(beam[0])
    assert_eq(SavedWorld.read(_snapshot, _editstore).save(source, _store()), "", "the save succeeds")

    var world := _world()
    assert_true(SavedWorld.read(_snapshot, _editstore).load_into(world, _store()), "and loads")

    assert_eq(world.index.count(), 2, "both parts came back")
    assert_eq(world.index.part_at(beam[0]), -1, "the carved cell is still no one's")
    for cell in beam.slice(1) + brace:
        assert_eq(world.index.part_at(cell), source.index.part_at(cell), "cell %s keeps its owner" % cell)
    for id in [beam_id, brace_id]:
        _assert_same_record(world.index.record(id), source.index.record(id))

    var fresh: Array[Vector3i] = [Vector3i(9, 9, 9)]
    _place(fresh, &"Wood", Transform3D.IDENTITY)
    assert_eq(world.index.part_at(fresh[0]), source.index.part_at(fresh[0]),
        "the next placement gets the id the saved world would have issued")
    assert_gt(world.index.part_at(fresh[0]), brace_id, "past every saved id, so none is reused")


# restore() trusts its input, so a snapshot whose index breaks the one-owner invariant is refused
# whole rather than loaded with one record silently losing a cell to another.
func test_a_snapshot_whose_parts_share_a_cell_is_refused() -> void:
    var source := _world()
    var beam:  Array[Vector3i] = [Vector3i(1, 2, 3), Vector3i(2, 2, 3)]
    var brace: Array[Vector3i] = [Vector3i(3, 3, 3)]
    _place(beam, &"Wood", Transform3D.IDENTITY)
    _place(brace, &"Stone", Transform3D.IDENTITY)
    assert_eq(SavedWorld.read(_snapshot, _editstore).save(source, _store()), "", "the save succeeds")

    var snap  := WorldSnapshot.read(_snapshot)
    var parts: Dictionary = bytes_to_var(snap["parts"])
    parts["records"][1]["cells"].append(beam[0])
    snap["parts"] = var_to_bytes(parts)
    FileAccess.open(_snapshot, FileAccess.WRITE).store_string(var_to_str(snap))

    var saved := SavedWorld.read(_snapshot, _editstore)
    assert_string_contains(saved.refusal, "both claim cell", "the shared cell is named")
    assert_false(saved.load_into(_world(), _store()), "and nothing is applied")
