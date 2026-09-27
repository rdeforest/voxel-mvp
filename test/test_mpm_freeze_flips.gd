extends GutTest

# The MPM freeze announces the cells its write flipped, measured across it (MpmSim.rasterize_to_store
# returns EditStore.write_region_flips's keys): whole in one event for a small freeze, split by
# re-mesh chunk for a large one. Each is checked against the store's solidity read before and after
# the freeze, independently of the code under test. And the subscribers that follow flips hear it:
# PartIndex releases a part cell the freeze empties, TerrainSupport tracks the cells it made solid
# with the material they hold. docs/roadmap/design/12-mpm-structural-substrate.md, "The freeze (as built)".
# (Drafted by Claude, overnight 2026-09-27.)

const MatterLog := preload("res://test/support/matter_log.gd")

var _log:   MatterLog
var _store: EditStoreManager


func before_each() -> void:
    _log   = MatterLog.new()
    _store = EditStoreManager.new()
    _store.setup()


func after_each() -> void:
    _log = null


func _top(x: float, z: float) -> float:
    return EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


func _sky() -> Vector3i:
    return Vector3i(0, int(_top(0.0, 0.0)) + 20, 0)


func _mpm() -> MpmStructure:
    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(_store.store)
    return ms


# Particles filling the cells of the box [lo, lo + size), eight per cell as a thaw seeds them.
func _particles(ms: MpmStructure, lo: Vector3i, size: Vector3i, material: int) -> void:
    for z in size.z:
        for y in size.y:
            for x in size.x:
                var cell := Vector3(lo + Vector3i(x, y, z))
                for ox in [0.25, 0.75]:
                    for oy in [0.25, 0.75]:
                        for oz in [0.25, 0.75]:
                            ms._sim.add_particle(cell + Vector3(ox, oy, oz), 50.0, 0.125, material)


# A cell solid only through sub-metre leaves: a small ball around its sample point, every 1 m
# lattice point around it air. A freeze whose region covers it re-reads the field at 1 m and
# rewrites it there, so the cell goes air (docs/bugs/edit-store-1m-write-flattens-finer-leaves.md).
func _sliver(cell: Vector3i) -> void:
    _store.store.stamp_sphere(VoxelUtils.sample_point(cell), 0.35, VoxelConstants.STORE_OP_UNION,
        MaterialPalette.index_of(&"Wood"), 0.25)
    assert_true(TerrainProbe.is_solid(_store.store, cell), "precondition: the sliver makes its cell solid")


func _solidity(lo: Vector3i, hi: Vector3i) -> Dictionary:
    var out := {}
    for z in range(lo.z, hi.z + 1):
        for y in range(lo.y, hi.y + 1):
            for x in range(lo.x, hi.x + 1):
                var cell := Vector3i(x, y, z)
                out[cell] = TerrainProbe.is_solid(_store.store, cell)
    return out


# {solid, air}: the cells whose solidity differs between two _solidity reads.
func _flipped(was: Dictionary, now: Dictionary) -> Dictionary:
    var out := {"solid": [], "air": []}
    for cell: Vector3i in was:
        if now[cell] and not was[cell]:
            out.solid.append(cell)
        elif was[cell] and not now[cell]:
            out.air.append(cell)
    return out


func _sorted(cells: Array) -> Array:
    var out := cells.duplicate()
    out.sort()
    return out


func _drain(ms: MpmStructure) -> void:
    while not ms._pending_chunks.is_empty():
        ms.tick(1.0 / 60.0)


func _mpm_events() -> Array[TerrainSdfChangedEvent]:
    return _log.events.filter(func(e: TerrainSdfChangedEvent) -> bool: return e.source == EditSource.Kind.MPM)


func _inside(box: AABB, lo: Vector3i, hi: Vector3i) -> bool:
    return box.position.x >= lo.x and box.position.y >= lo.y and box.position.z >= lo.z \
        and box.end.x <= hi.x + 1 and box.end.y <= hi.y + 1 and box.end.z <= hi.z + 1


# A terrain thaw that falls into its own hole and freezes there: the one event's flips are the
# cells the freeze changed. The sim writes nothing between the thaw and the freeze, so the store
# read after the thaw is the freeze's "before".
func test_a_freeze_announces_the_cells_it_flipped() -> void:
    var ms     := _mpm()
    var center := Vector3i(0, int(_top(0.5, 0.5)) - 3, 0)
    assert_gt(ms.thaw_sphere(Vector3(center) + Vector3.ONE * 0.5, 3.0, EditSource.Kind.INSTRUMENT), 0,
        "precondition: the thaw emptied cells")
    var lo  := center - Vector3i.ONE * 12
    var hi  := center + Vector3i.ONE * 12
    var was := _solidity(lo, hi)
    _log.clear()

    for _i in 1500:
        ms.tick(1.0 / 60.0)
        if ms.active_count() == 0:
            break
    _drain(ms)

    var events := _mpm_events()
    assert_eq(events.size(), 1, "precondition: a small freeze, one event")
    assert_true(_inside(AABB(events[0].box_origin, events[0].box_size), lo, hi), "precondition: its box was read")
    var want := _flipped(was, _solidity(lo, hi))
    assert_false(want.solid.is_empty(), "precondition: the freeze made cells solid")
    assert_eq(_sorted(events[0].flips.solid), _sorted(want.solid), "the event's solid flips are the cells that went solid")
    assert_eq(_sorted(events[0].flips.air), _sorted(want.air), "and its air flips the cells that went air")
    assert_true(events[0].flips.changed, "the write moved samples")


# Two clumps far enough apart that the region is chunked, and a sliver the rewrite empties: each
# chunk's event carries exactly the flips inside its own box, and together they are the write's.
func test_a_chunked_freezes_flips_partition_the_write() -> void:
    var ms   := _mpm()
    var sky  := _sky()
    var wood := MaterialPalette.index_of(&"Wood")
    _particles(ms, sky, Vector3i(2, 2, 2), wood)
    _particles(ms, sky + Vector3i(26, 0, 3), Vector3i(2, 2, 2), wood)
    var sliver := sky + Vector3i(14, 1, 1)
    _sliver(sliver)
    var lo  := sky - Vector3i.ONE * 3
    var hi  := sky + Vector3i.ONE * 34   # the region's chunk boxes, whole
    var was := _solidity(lo, hi)

    ms._freeze()
    assert_false(ms._pending_chunks.is_empty(), "precondition: the region is chunked")
    _drain(ms)

    var want   := _flipped(was, _solidity(lo, hi))
    var events := _mpm_events()
    assert_eq(want.air, [sliver], "precondition: the rewrite emptied the sliver's cell")
    var solid: Array = []
    var air:   Array = []
    for e in events:
        var box := AABB(e.box_origin, e.box_size)
        assert_true(_inside(box, lo, hi), "precondition: every chunk's box was read")
        for cell: Vector3i in e.flips.solid + e.flips.air:
            assert_true(box.has_point(Vector3(cell) + Vector3.ONE * 0.5), "%s flips inside its own chunk" % cell)
        assert_eq(e.flips.air_materials.size(), e.flips.air.size(), "each air flip carries its material")
        solid.append_array(e.flips.solid)
        air.append_array(e.flips.air)
    assert_gt(events.size(), 1, "precondition: more than one chunk")
    assert_eq(_sorted(solid), _sorted(want.solid), "the chunks' solid flips are the cells that went solid, once each")
    assert_eq(air, [sliver], "and the one air flip is the emptied cell")
    assert_eq(events.filter(func(e: TerrainSdfChangedEvent) -> bool: return not e.flips.air.is_empty())[0] \
        .flips.air_materials, PackedByteArray([wood]), "with what it was made of")


# A part cell the freeze's rewrite empties leaves its part, as a dig's would.
func test_part_index_hears_a_part_cell_the_freeze_empties() -> void:
    var index  := PartIndex.new()
    var ms     := _mpm()
    var sky    := _sky()
    var sliver := sky + Vector3i(3, 0, 0)   # inside the region, past the particles' 0.6 m skin
    _sliver(sliver)
    VoxelEventBusSingleton.emit(PartPlacedEvent.CHANNEL, PartPlacedEvent.new(VoxelConstants.GRID_ID,
        [sliver] as Array[Vector3i], &"Wood", Vector3.ONE * 0.7, Transform3D.IDENTITY))
    assert_eq(index.count(), 1, "precondition: the part is recorded")
    _particles(ms, sky, Vector3i(2, 2, 2), MaterialPalette.index_of(&"Stone"))

    ms._freeze()
    _drain(ms)

    assert_false(TerrainProbe.is_solid(_store.store, sliver), "precondition: the freeze emptied the part's cell")
    assert_eq(index.count(), 0, "the part left with its only cell")


# TerrainSupport tracks every cell the freeze made solid, with what it is made of: its box scan used
# to register only the exposed ones, as Stone.
func test_terrain_support_tracks_the_frozen_cells_as_what_they_are() -> void:
    var support := TerrainSupport.new()
    support.store = _store.store
    var ms  := _mpm()
    var sky := _sky()
    _particles(ms, sky, Vector3i(3, 3, 3), MaterialPalette.index_of(&"Wood"))
    var lo  := sky - Vector3i.ONE * 4
    var hi  := sky + Vector3i.ONE * 7
    var was := _solidity(lo, hi)

    ms._freeze()
    _drain(ms)

    var made: Array = _flipped(was, _solidity(lo, hi)).solid
    assert_true(made.has(sky + Vector3i.ONE), "precondition: the clump's middle cell froze solid")
    for cell: Vector3i in made:
        assert_true(support.voxel_data.has(cell), "%s is tracked" % cell)
        if support.voxel_data.has(cell):
            assert_eq(support.voxel_data[cell].material, Materials.WOOD, "%s as Wood" % cell)


# A chunked freeze announces its flips frames after its write. A part placed in between on a cell
# the freeze emptied is released when that chunk's air flip arrives
# (docs/bugs/mpm-chunked-freeze-flips-arrive-late.md). Pending while it reproduces; it then asserts.
func test_a_part_placed_before_a_chunked_freeze_is_announced_keeps_its_cell() -> void:
    var index  := PartIndex.new()
    var ms     := _mpm()
    var sky    := _sky()
    _particles(ms, sky, Vector3i(2, 2, 2), MaterialPalette.index_of(&"Stone"))
    _particles(ms, sky + Vector3i(26, 0, 3), Vector3i(2, 2, 2), MaterialPalette.index_of(&"Stone"))
    var sliver := sky + Vector3i(14, 1, 1)
    _sliver(sliver)
    ms._freeze()
    assert_false(TerrainProbe.is_solid(_store.store, sliver), "precondition: the freeze emptied the cell")

    _store.store.stamp_box(VoxelUtils.sample_point(sliver), Vector3.ONE, VoxelConstants.STORE_OP_UNION,
        MaterialPalette.index_of(&"Wood"), 1.0)
    VoxelEventBusSingleton.emit(PartPlacedEvent.CHANNEL, PartPlacedEvent.new(VoxelConstants.GRID_ID,
        [sliver] as Array[Vector3i], &"Wood", Vector3.ONE, Transform3D.IDENTITY))
    assert_eq(index.count(), 1, "precondition: a part now owns the cell")
    _drain(ms)

    if index.count() == 0:
        var late := _mpm_events().filter(func(e: TerrainSdfChangedEvent) -> bool: return e.flips.air.has(sliver))
        assert_eq(late.size(), 1, "the release came with the freeze chunk carrying the cell's air flip")
        pending("docs/bugs/mpm-chunked-freeze-flips-arrive-late.md: the late air flip released a live part cell")
        return
    assert_true(TerrainProbe.is_solid(_store.store, sliver), "the cell is solid")
    assert_eq(index.count(), 1, "and still the part's")
