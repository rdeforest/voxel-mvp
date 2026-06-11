extends GutTest

# PartIndex identity sidecar: records placements (PartPlacedEvent), tracks cell ownership,
# drops carved cells (VoxelRemovedEvent), and answers count / part_at / record.

func _place(cells: Array[Vector3i], material: StringName) -> void:
    VoxelEventBusSingleton.emit(
        PartPlacedEvent.CHANNEL,
        PartPlacedEvent.new(0, cells, material, Vector3(6, 2, 2), Transform3D.IDENTITY))

func _carve(cell: Vector3i) -> void:
    VoxelEventBusSingleton.emit(VoxelRemovedEvent.CHANNEL, VoxelRemovedEvent.new(0, cell))


func test_records_a_placement() -> void:
    var index := PartIndex.new()
    var cells: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)]
    _place(cells, &"Wood")
    assert_eq(index.count(), 1, "the placement was recorded")
    var id := index.part_at(Vector3i(1, 0, 0))
    assert_gt(id, 0, "the cell maps to a part id")
    var record := index.record(id)
    assert_eq(record.material, &"Wood", "the record carries the material")
    assert_eq(record.cells.size(), 3, "and all its cells")


func test_carving_shrinks_then_drops_the_part() -> void:
    var index := PartIndex.new()
    var cells: Array[Vector3i] = [Vector3i(5, 5, 5), Vector3i(6, 5, 5)]
    _place(cells, &"Stone")
    var id := index.part_at(Vector3i(5, 5, 5))
    _carve(Vector3i(5, 5, 5))
    assert_eq(index.part_at(Vector3i(5, 5, 5)), -1, "the carved cell left the part")
    assert_eq(index.record(id).cells.size(), 1, "the part shrank to its remaining cell")
    _carve(Vector3i(6, 5, 5))
    assert_eq(index.count(), 0, "a fully-carved part is dropped")


func test_newest_part_claims_an_overlapped_cell() -> void:
    var index := PartIndex.new()
    var single: Array[Vector3i] = [Vector3i(9, 9, 9)]
    _place(single, &"Wood")
    var first := index.part_at(Vector3i(9, 9, 9))
    _place(single, &"Stone")
    var second := index.part_at(Vector3i(9, 9, 9))
    assert_ne(first, second, "the overlapped cell now belongs to the newer part")
    assert_null(index.record(first), "the first part lost its only cell and was dropped")
