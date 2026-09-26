extends GutTest

# Gate for the flips a write measures across itself, which every event-reporting writer now takes
# from EditStore (C++, write_region_flips, through SdfLattice.write): FillAction, DigAction,
# VoxelImprint.apply (CSG, construction), StoreWrite.write (FillVoxel / EmptyVoxel, the MPM thaw).
# It must be the GDScript measurement it replaced (CellFlips.snapshot / since around write_region,
# with the thaw's _solid_materials and _changed; the oracle, test/support/lattice_oracle.gd) exactly:
# the same solid and air lists in the same order, the same pre-write material per emptied cell, the
# same `changed`, and the same store afterwards — for sphere stamps, imprints of every shape under
# turns, thaw carves and single-voxel fills and empties, on the multi-level store the prediction
# gates use (test/support/predict_store.gd). Each lattice is then written a second time, where the
# field is already what it writes, so `changed` is compared false as well as true.
#
# Mutations of the C++ this catches: reading "before" after the write, x-y-z cell order, emptied
# cells' materials read after the write or dropped, `changed` true only on a flip, and either
# threshold comparison made strict (the zeroed cell). One it cannot: dropping the first candidate
# cell per axis in rewritten_cells, which only a lattice off the 1 m grid (origin or cell) reaches,
# and no writer builds one.
# (Drafted by Claude, overnight 2026-09-26.)

const Oracle       := preload("res://test/support/lattice_oracle.gd")
const PredictStore := preload("res://test/support/predict_store.gd")

const PAINTS := [1, 4, 5, 3, 0]   # Stone, Wood, Metal, Sand, Natural

var _fixture:    PredictStore
var _store:      EditStore
var _mismatches: Array[String] = []
var _counts:     Dictionary    = {}
var _cases:      int           = 0


func before_each() -> void:
    _fixture = PredictStore.new()
    _store   = _fixture.store
    _mismatches.clear()
    _counts  = {"solid": 0, "air": 0, "air_material": 0, "changed_no_flip": 0, "unchanged": 0}
    _cases   = 0


# `game_write(store)` is the game's write of `lat` (returning its measured CellFlips); the oracle
# writes the same lattice with `indices`. Both run on their own copy of the store, twice.
func _same(label: String, lat: SdfLattice, indices: PackedByteArray, game_write: Callable) -> void:
    var game   := _store.duplicate()
    var oracle := _store.duplicate()
    for pass_index in 2:
        var got: CellFlips  = game_write.call(game)
        var want: CellFlips = Oracle.measured_write(lat, oracle, indices)
        var where := "%s pass %d" % [label, pass_index]
        _check_flips(where, got, want)
        _tally(want)
    if game.serialize() != oracle.serialize():
        _mismatches.append("%s: the stores differ after the writes" % label)
    _cases += 1


func _check_flips(where: String, got: CellFlips, want: CellFlips) -> void:
    if got.solid != want.solid:
        _mismatches.append("%s solid: %s vs %s" % [where, got.solid, want.solid])
    if got.air != want.air:
        _mismatches.append("%s air: %s vs %s" % [where, got.air, want.air])
    if got.air_materials != want.air_materials:
        _mismatches.append("%s air_materials: %s vs %s" % [where, got.air_materials, want.air_materials])
    if got.changed != want.changed:
        _mismatches.append("%s changed: %s vs %s" % [where, got.changed, want.changed])


func _tally(want: CellFlips) -> void:
    _counts.solid += want.solid.size()
    _counts.air   += want.air.size()
    for m in want.air_materials:
        if m != 0:
            _counts.air_material += 1
    if want.changed and want.is_empty():
        _counts.changed_no_flip += 1
    if not want.changed:
        _counts.unchanged += 1


func _assert_all_same(minimums: Dictionary) -> void:
    assert_eq(_mismatches.size(), 0, "the game matches the oracle exactly:\n" + "\n".join(_mismatches.slice(0, 10)))
    for key: String in minimums:
        assert_gt(_counts[key], minimums[key], "%s over %d cases (else that path is compared empty)" % [key, _cases])


func _brush_write(lat: SdfLattice, indices: PackedByteArray) -> Callable:
    return func(store: EditStore) -> CellFlips: return lat.write(store, indices)


# FillAction and DigAction: the sphere stamp, painted as each paints it.
func test_sphere_stamp_flips_match_oracle() -> void:
    for p in _fixture.positions():
        for radius: float in [1.0, 2.5, 3.7]:
            for op in [VoxelConstants.STORE_OP_UNION, VoxelConstants.STORE_OP_SUBTRACT]:
                var lat := SdfLattice.sphere_stamp(_store, p, radius, op, VoxelConstants.RENDER_BASE_CELL)
                var material: int = PAINTS[_cases % PAINTS.size()] if op == VoxelConstants.STORE_OP_UNION else -1
                var indices := lat.materials(_store, material, true)
                _same("sphere %s r%s op%d" % [p, radius, op], lat, indices, _brush_write(lat, indices))
    _assert_all_same({"solid": 800, "air": 800, "air_material": 800, "changed_no_flip": 5, "unchanged": 60})


func _shapes() -> Array[CsgShape]:
    return [
        CsgBoxShape.new(Vector3(4.0, 4.0, 4.0)),
        CsgBoxShape.new(Vector3(3.0, 0.2, 0.7)),
        CsgCylinderShape.new(0.7, 3.3),
        CsgSphereShape.new(1.3),
    ]


# VoxelImprint.apply (CSG stamps and part placements): its lattice, painted as it paints it.
func test_imprint_flips_match_oracle() -> void:
    var turns: Array[Basis] = [Basis(), Basis(Vector3.UP, PI * 0.25), Basis(Vector3(0.3, 1.0, 0.2).normalized(), 0.7)]
    for shape in _shapes():
        for p in _fixture.positions():
            var xform := Transform3D(turns[_cases % turns.size()], p)
            for op in [CsgState.Op.ADD, CsgState.Op.SUBTRACT]:
                var lat := VoxelImprint.lattice(_store, shape, xform, op)
                var part: int = PAINTS[_cases % PAINTS.size()] if op == CsgState.Op.ADD else -1
                var indices := lat.materials(_store, part, false)
                _same("imprint %s %s at %s op%d" % [shape.sdf_kind(), shape.sdf_dims(), xform, op], lat, indices,
                    _brush_write(lat, indices))
    _assert_all_same({"solid": 250, "air": 300, "air_material": 300, "changed_no_flip": 3, "unchanged": 80})


# StoreWrite.write, the path FillVoxel / EmptyVoxel and the thaw take, with the oracle handed the
# indices StoreWrite paints (the stores compared afterwards confirm they are the same).
func _same_work(label: String, work: Array[LatticeEdit]) -> void:
    var lat     := StoreWrite.lattice(_store, work)
    var indices := StoreWrite._current_materials(_store, lat)
    for edit in work:
        if edit.material >= 0:
            indices[lat.index(edit.point - Vector3i(lat.origin))] = edit.material
    _same(label, lat, indices, func(store: EditStore) -> CellFlips: return StoreWrite.write(store, lat, work))


# MpmStructure.thaw_cells' carve, over balls of cells through the edit history and the surface.
func test_thaw_flips_match_oracle() -> void:
    var ms: MpmStructure = autofree(MpmStructure.new())
    ms.setup(_store)
    for p in _fixture.positions():
        for radius: float in [0.9, 2.2, 3.5]:
            var work := ms._carve_corners(ms._plan_thaw(VoxelUtils.cells_in_sphere(p, radius)))
            if not work.is_empty():
                _same_work("thaw %s r%s" % [p, radius], work)
    _assert_all_same({"air": 500, "air_material": 500, "unchanged": 20})


# FillVoxel / EmptyVoxel: StoreWrite.one_cell's work for the cells around each position.
func test_single_voxel_flips_match_oracle() -> void:
    var offsets: Array[Vector3i] = [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 1),
        Vector3i(-1, 1, -1)]
    for p in _fixture.positions():
        for offset in offsets:
            var cell  := Vector3i(p.floor()) + offset
            var solid := not TerrainProbe.is_solid(_store, cell)
            var work  := StoreWrite.one_cell(_store, cell, solid, PAINTS[_cases % PAINTS.size()] if solid else -1)
            if not work.is_empty():
                _same_work("one_cell %s solid %s" % [cell, solid], work)
    _assert_all_same({"solid": 15, "air": 12, "air_material": 12, "unchanged": 50})


# A cell whose sample is exactly the threshold counts as air (CellFlips._add: solid is < it), so a
# write from exactly zero to solid flips it solid and one from solid to exactly zero flips it air.
# Real fields reach exactly zero only through a written corner; the cell here is zeroed first.
func test_threshold_cell_flips_match_oracle() -> void:
    var cell := Vector3i(_fixture.base) + Vector3i(0, 1, 0)
    StoreWrite.cells(_store, _corners(cell, 0.0))
    assert_eq(TerrainProbe.sdf(_store, cell), 0.0, "the cell's sample is exactly the threshold")
    _same_work("zero to solid", _corners(cell, -0.3))

    StoreWrite.cells(_store, _corners(cell, -0.3))
    _same_work("solid to zero", _corners(cell, 0.0))
    _assert_all_same({"solid": 0, "air": 0})


func _corners(cell: Vector3i, sdf: float) -> Array[LatticeEdit]:
    var work: Array[LatticeEdit] = []
    for k in 8:
        work.append(LatticeEdit.new(cell + Vector3i(CubeGeometry.corner(k)), sdf))
    return work


# A lattice EditStore refuses (sdf not dim^3) writes nothing and measures nothing, with its error,
# rather than aborting the writer on a result it can't read.
func test_refused_lattice_writes_nothing() -> void:
    var lat    := SdfLattice.new(_fixture.base, 1.0, 3)
    var before := _store.serialize()
    lat.sdf.resize(5)

    var got := lat.write(_store, PackedByteArray())
    assert_engine_error("Not a lattice")
    assert_true(got.is_empty(), "no flips")
    assert_false(got.changed, "nothing changed")
    assert_eq(_store.serialize(), before, "the store is untouched")
