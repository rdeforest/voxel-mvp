extends GutTest

# Gate for the preview predictions, which the game runs in EditStore (C++) every frame: the
# lattice each writer builds (SdfLattice.sphere_stamp, VoxelImprint.lattice, StoreWrite.lattice,
# the raise / lower / flatten reshapes) and the questions asked of it (SdfLattice.flips,
# solidifies_in / empties_in) must reproduce the GDScript originals BIT FOR BIT — every float32 of
# the lattice by its bytes, the same flipped cells in the same order, the same safety answer. A
# preview that differs from the write by one ulp can name a cell the write doesn't flip. The
# originals live on as the oracle (test/support/lattice_oracle.gd), an independent implementation.
#
# The store is the game's own under a multi-level edit history (test/support/predict_store.gd).

const Oracle       := preload("res://test/support/lattice_oracle.gd")
const PredictStore := preload("res://test/support/predict_store.gd")

const MIN_FLIPS := 200   # across a test's cases; far fewer means the cases stopped reaching the surface

var _fixture: PredictStore
var _store:   EditStore
var _base:    Vector3

var _mismatches: Array[String] = []
var _solid:      int           = 0
var _air:        int           = 0
var _no_writes:  int           = 0


func before_each() -> void:
    _fixture   = PredictStore.new()
    _store     = _fixture.store
    _base      = _fixture.base
    _mismatches.clear()
    _solid     = 0
    _air       = 0
    _no_writes = 0


func _positions() -> Array[Vector3]:
    return _fixture.positions()


# The game's lattice (and its flips) against the oracle's.
func _same(label: String, want: SdfLattice, got: SdfLattice) -> void:
    if got == null:
        _mismatches.append("%s: the game refused the prediction" % label)
        return
    for key: String in ["origin", "cell", "dim", "writes"]:
        if got.get(key) != want.get(key):
            _mismatches.append("%s: %s = %s, oracle %s" % [label, key, got.get(key), want.get(key)])
    if got.sdf.to_byte_array() != want.sdf.to_byte_array():
        _mismatches.append("%s: sdf differs (%s)" % [label, _first_difference(got.sdf, want.sdf)])
    var want_flips := Oracle.flips(want, _store)
    var got_flips  := got.flips(_store)
    if got_flips.solid != want_flips.solid or got_flips.air != want_flips.air:
        _mismatches.append("%s: flips differ (solid %d vs %d, air %d vs %d)" % [label,
            got_flips.solid.size(), want_flips.solid.size(), got_flips.air.size(), want_flips.air.size()])
    _solid     += want_flips.solid.size()
    _air       += want_flips.air.size()
    _no_writes += 0 if want.writes else 1


func _first_difference(got: PackedFloat32Array, want: PackedFloat32Array) -> String:
    if got.size() != want.size():
        return "size %d vs %d" % [got.size(), want.size()]
    for i in want.size():
        if var_to_bytes(got[i]) != var_to_bytes(want[i]):
            return "index %d: %.12f vs %.12f" % [i, got[i], want[i]]
    return "a zero's sign"


func _assert_all_same(min_no_writes: int) -> void:
    assert_eq(_mismatches.size(), 0, "the game matches the oracle bit for bit:\n" + "\n".join(_mismatches.slice(0, 10)))
    assert_gt(_solid + _air, MIN_FLIPS, "the cases flip cells (else the flip lists are compared empty)")
    assert_gt(_solid, 0, "some case flips a cell solid")
    assert_gt(_air, 0, "some case flips a cell to air")
    assert_gte(_no_writes, min_no_writes, "some case writes nothing (the writes flag is exercised both ways)")


func test_edit_history_is_multi_level() -> void:
    for p in _positions().slice(0, 7):
        assert_true(_store.has_edit(p), "position %s sits in edited leaves" % p)
    assert_false(_store.has_edit(_base + Vector3(20.0, 0.0, 20.0)), "and the generator is next door")


func test_sphere_stamp_matches_oracle() -> void:
    var radii := {
        VoxelConstants.RENDER_BASE_CELL: [1.0, 1.5, 2.5, 3.0, 3.7],
        0.5:                             [1.0, 2.5],
        0.25:                            [1.5],
    }
    for leaf: float in radii:
        for p in _positions():
            for radius: float in radii[leaf]:
                for op in [VoxelConstants.STORE_OP_UNION, VoxelConstants.STORE_OP_SUBTRACT]:
                    _same("sphere %s r%s op%d leaf%s" % [p, radius, op, leaf],
                        Oracle.sphere_stamp(_store, p, radius, op, leaf),
                        SdfLattice.sphere_stamp(_store, p, radius, op, leaf))
    _assert_all_same(1)


func _shapes() -> Array[CsgShape]:
    return [
        CsgBoxShape.new(Vector3(4.0, 4.0, 4.0)),
        CsgBoxShape.new(Vector3(0.5, 0.5, 4.0)),
        CsgBoxShape.new(Vector3(12.0, 3.0, 7.0)),
        CsgCylinderShape.new(2.0, 5.0),
        CsgCylinderShape.new(0.7, 3.3),
        CsgSphereShape.new(3.0),
        CsgSphereShape.new(1.3),
        CsgSphereShape.new(6.5),
    ]


func test_imprint_matches_oracle() -> void:
    var bases: Array[Basis] = [
        Basis(),
        Basis(Vector3.UP, PI * 0.25),
        Basis(Vector3(0.3, 1.0, 0.2).normalized(), 0.7),
    ]
    for shape in _shapes():
        for p in _positions():
            for basis in bases:
                var xform := Transform3D(basis, p)
                for op in [CsgState.Op.ADD, CsgState.Op.SUBTRACT]:
                    _same("imprint %s %s at %s op%d" % [shape.sdf_kind(), shape.sdf_dims(), xform, op],
                        Oracle.imprint(_store, shape, xform, op), VoxelImprint.lattice(_store, shape, xform, op))
    _assert_all_same(1)


func _normals() -> Array[Vector3]:
    return [Vector3.UP, Vector3(0.4, 1.0, -0.3).normalized(), Vector3(1.0, 0.2, 0.0).normalized()]


func _work_sets() -> Array:
    var sets: Array = []
    for p in _positions():
        for radius: float in [1.5, 3.0, 3.7]:
            sets.append(["raise %s r%s" % [p, radius], Oracle.bell_work(_store, p, radius, -1.0)])
            sets.append(["flatten %s r%s" % [p, radius], Oracle.flatten_work(_store, p, Vector3.UP, radius)])
    for c in [Vector3i(_base), Vector3i(_base) + Vector3i(1, -1, 0), Vector3i(_base) + Vector3i(0, 1, 2)]:
        for solid in [true, false]:
            sets.append(["one_cell %s %s" % [c, solid], StoreWrite.one_cell(_store, c, solid)])
    var b := Vector3i(_base)
    var repeated: Array[LatticeEdit] = [
        LatticeEdit.new(b, 0.1),
        LatticeEdit.new(b + Vector3i(2, 0, -1), -0.3),
        LatticeEdit.new(b, _store.sample(Vector3(b))),
    ]
    sets.append(["a point written twice, the second time with its current value", repeated])
    var unchanged: Array[LatticeEdit] = [LatticeEdit.new(b, float(PackedFloat32Array([_store.sample(Vector3(b))])[0]))]
    sets.append(["a point rewritten to its own float32 value", unchanged])
    var near: Array[LatticeEdit] = [LatticeEdit.new(b, unchanged[0].sdf + 1e-12)]
    sets.append(["a point rewritten to a double that rounds to its own float32 value", near])
    return sets


func test_work_matches_oracle() -> void:
    for entry: Array in _work_sets():
        var work: Array[LatticeEdit] = entry[1]
        if not work.is_empty():
            _same(entry[0], Oracle.work(_store, work), StoreWrite.lattice(_store, work))
    _assert_all_same(1)


# The game's reshape lattice (null when it writes no point) against the oracle's work set.
func _same_reshape(label: String, work: Array[LatticeEdit], got: SdfLattice) -> void:
    if work.is_empty():
        if got != null:
            _mismatches.append("%s: the oracle writes no point, the game writes a lattice" % label)
        _no_writes += 1
        return
    _same(label, Oracle.work(_store, work), got)


func test_bell_matches_oracle() -> void:
    var ctx := ActionContext.new(_store, null, null)
    for p in _positions():
        for radius: float in [0.4, 1.5, 3.0, 3.7]:
            for action: BellSculptAction in [RaiseAction.new(p, radius, ctx), LowerAction.new(p, radius, ctx)]:
                action._ensure_lattice()
                _same_reshape("bell %s r%s sign%s" % [p, radius, action._sign],
                    Oracle.bell_work(_store, p, radius, action._sign), action._lattice)
    _assert_all_same(1)


func test_flatten_matches_oracle() -> void:
    var ctx := ActionContext.new(_store, null, null)
    for p in _positions():
        for radius: float in [1.5, 3.0, 3.7]:
            for normal in _normals():
                var action := FlattenAction.new(p, normal, radius, ctx)
                action._ensure_lattice()
                _same_reshape("flatten %s n%s r%s" % [p, normal, radius],
                    Oracle.flatten_work(_store, p, action.normal, radius), action._lattice)
    _assert_all_same(1)


# Player-safety boxes around each brush: centred on it, at its edge (boxes over rewritten leaves,
# where the whole scan runs), straddling its rim, and clear of it.
func _safety_boxes(at: Vector3) -> Array[AABB]:
    var boxes: Array[AABB] = []
    for offset in [Vector3.ZERO, Vector3(4.5, 1.5, 0.0), Vector3(2.3, -0.7, 1.1), Vector3(0.0, 3.2, -2.9),
            Vector3(-3.6, 0.4, 0.25), Vector3(12.0, 0.0, 0.0)]:
        boxes.append(PlayerSafeAction.capsule_box(at + offset))
        boxes.append(PlayerSafeAction.support_box(at + offset))
    boxes.append(AABB(at + Vector3(0.1, 0.2, 0.3), Vector3(0.05, 0.05, 0.05)))
    return boxes


func _safety_lattices(p: Vector3) -> Array:
    var ctx   := ActionContext.new(_store, null, null)
    var raise := RaiseAction.new(p, 3.0, ctx)
    raise._ensure_lattice()
    return [
        ["dig", Oracle.sphere_stamp(_store, p, 3.0, VoxelConstants.STORE_OP_SUBTRACT, 1.0)],
        ["fill", Oracle.sphere_stamp(_store, p, 2.5, VoxelConstants.STORE_OP_UNION, 1.0)],
        ["fine fill", Oracle.sphere_stamp(_store, p, 1.5, VoxelConstants.STORE_OP_UNION, 0.25)],
        ["csg box", Oracle.imprint(_store, CsgBoxShape.new(Vector3(0.5, 0.5, 4.0)),
            Transform3D(Basis(Vector3.UP, 0.6), p), CsgState.Op.ADD)],
        ["raise", raise._lattice],
    ]


func test_safety_matches_oracle() -> void:
    var answers := {true: 0, false: 0}
    for p in _positions():
        for entry: Array in _safety_lattices(p):
            var lat: SdfLattice = entry[1]
            if lat == null:
                continue
            for box in _safety_boxes(p):
                for to_solid in [true, false]:
                    var want := Oracle.turns_in(lat, _store, box, to_solid)
                    var got  := lat.solidifies_in(_store, box) if to_solid else lat.empties_in(_store, box)
                    answers[want] += 1
                    if got != want:
                        _mismatches.append("%s at %s, box %s, to_solid %s: game %s, oracle %s" % [
                            entry[0], p, box, to_solid, got, want])
    assert_eq(_mismatches.size(), 0, "the game matches the oracle:\n" + "\n".join(_mismatches.slice(0, 10)))
    assert_gt(answers[true], 50, "the cases endanger the player (else only 'no' is compared)")
    assert_gt(answers[false], 50, "and leave them safe")


# A cell whose trilerp lands EXACTLY on SDF_SOLID_THRESHOLD, before or after the write: the one
# place a >= / > slip in the flip test changes the answer. All 8 corners at 0.0 make the sample
# point's value exactly 0.0 on both sides.
func _zero_corners(c: Vector3i, value: float) -> Array[LatticeEdit]:
    var out: Array[LatticeEdit] = []
    for k in 8:
        out.append(LatticeEdit.new(c + Vector3i(CubeGeometry.corner(k)), value))
    return out


func _threshold_case(label: String, c: Vector3i, value: float, want_solid: bool, want_air: bool) -> void:
    var work  := _zero_corners(c, value)
    var flips := Oracle.flips(Oracle.work(_store, work), _store)
    assert_eq(flips.solid.has(c), want_solid, "%s: the oracle flips it solid = %s" % [label, want_solid])
    assert_eq(flips.air.has(c), want_air, "%s: the oracle flips it to air = %s" % [label, want_air])
    _same(label, Oracle.work(_store, work), StoreWrite.lattice(_store, work))


func test_exact_threshold_flips_match_oracle() -> void:
    var t      := VoxelConstants.SDF_SOLID_THRESHOLD
    var solid  := Vector3i(_base) + Vector3i(0, -6, 0)
    var air    := Vector3i(_base) + Vector3i(0, 6, 0)
    var at_t   := Vector3i(_base) + Vector3i(4, -6, 4)
    assert_lt(_store.sample(VoxelUtils.sample_point(solid)), t, "the solid case starts solid")
    assert_gte(_store.sample(VoxelUtils.sample_point(air)), t, "the air case starts air")
    _threshold_case("now == t over solid", solid, t, false, true)
    _threshold_case("now == t over air", air, t, false, false)

    Oracle.work(_store, _zero_corners(at_t, t)).write(_store, PackedByteArray())
    assert_eq(_store.sample(VoxelUtils.sample_point(at_t)), t, "the store now holds exactly t there")
    _threshold_case("was == t, written solid", at_t, VoxelConstants.SDF_SOLID, true, false)
    _threshold_case("was == t, written air", at_t, VoxelConstants.SDF_AIR, false, false)
    assert_eq(_mismatches.size(), 0, "the game matches the oracle at the threshold:\n" + "\n".join(_mismatches))
