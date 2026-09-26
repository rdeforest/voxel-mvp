extends GutTest

# Gate for ConstructionAction's attach test, which the game runs in EditStore (C++,
# imprint_near_solid) every preview: it must give the GDScript original's answer (the oracle,
# test/support/lattice_oracle.gd) for every placement, and so refuse exactly the placements the
# original refused. Asked of the store test_edit_store_predict gates on (test/support/predict_store.gd).
#
# Answers are booleans, so agreement on arbitrary placements says little about bit-exactness. The
# boundary tests bisect the game's answer along a path down to adjacent doubles and ask the oracle
# both sides: a scan that differed anywhere by an ulp (brush SDF, lattice placement, store read)
# moves that boundary. The tie test pins the two comparisons at exact equality.
#
# A scan that skips the lattice's outermost planes passes this gate, and no gate could catch it:
# those planes lie at least VoxelImprint.MARGIN plus a cell beyond the shape's box, and reach is
# under a cell, so no point there attaches. That holds while the brush SDF never underestimates
# distance outside the shape by more than MARGIN.
# (Drafted by Claude, overnight 2026-09-26.)

const Oracle       := preload("res://test/support/lattice_oracle.gd")
const PredictStore := preload("res://test/support/predict_store.gd")

const MIN_EACH := 40   # answers of each kind across the placement cases

var _fixture:    PredictStore
var _store:      EditStore
var _mismatches: Array[String] = []
var _answers:    Dictionary    = {}


func before_each() -> void:
    _fixture = PredictStore.new()
    _store   = _fixture.store
    _mismatches.clear()
    _answers = {true: 0, false: 0}


# The beam and the log, plus a plank thinner than a cell (it can attach without flipping a cell).
func _parts() -> Array[Part]:
    var plank := Part.new()
    plank.dimensions = Vector3(3.0, 0.2, 0.7)
    return [preload("res://assets/parts/beam/beam.tres"), preload("res://assets/parts/log/log.tres"), plank]


# Axis-aligned, yawed, compound, stood on end, and tilted (only its low end rests: partly attached).
func _rotations() -> Array[Vector3]:
    return [Vector3.ZERO, Vector3(0.0, 45.0, 0.0), Vector3(0.0, 27.0, 8.0), Vector3(30.0, 60.0, 15.0),
        Vector3(90.0, 0.0, 0.0), Vector3(0.0, 0.0, 35.0)]


# Generator ground next door: no edits within a part's reach.
func _open_ground() -> Vector3:
    var x := 120.0
    var z := 120.0
    return Vector3(x, EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED), z)


# The edited column's surface, the raised box's top and its edge (a part there overhangs), the dug
# pit, and open generator ground.
func _anchors() -> Array[Vector3]:
    var s := Vector3(100.0, _fixture.surface, 100.0)
    return [s, s + Vector3(3.0, 2.0, -2.0), s + Vector3(6.0, 2.0, -2.0), s + Vector3(-2.0, 0.0, 1.0),
        _open_ground()]


func _action(part: Part, at: Vector3, rot: Vector3) -> ConstructionAction:
    var action := ConstructionAction.new(part, at, rot, &"Wood", ActionContext.new(_store, null, null))
    action._ensure_flips()
    return action


# The game's attach answer and refusal against the oracle's; returns the oracle's answer.
func _same(label: String, action: ConstructionAction) -> bool:
    var shape := action._shape()
    var xform := action._xform()
    var want  := Oracle.attached(_store, Oracle.imprint(_store, shape, xform, CsgState.Op.ADD), shape, xform)
    if action._attached() != want:
        _mismatches.append("%s: game attached %s, oracle %s" % [label, not want, want])
    if action.validate() != want:
        _mismatches.append("%s: validate() %s, but the oracle's attached is %s (no player to endanger)" % [
            label, action.validate(), want])
    _answers[want] += 1
    return want


func _assert_no_mismatches() -> void:
    assert_eq(_mismatches.size(), 0, "the game matches the oracle:\n" + "\n".join(_mismatches.slice(0, 10)))


func test_placements_match_oracle() -> void:
    for part in _parts():
        for rot in _rotations():
            for anchor in _anchors():
                for lift: float in [-1.0, 0.0, 0.6, 1.5, 3.0, 8.0]:
                    _same("%s rot %s at %s +%s" % [part.dimensions, rot, anchor, lift],
                        _action(part, anchor + Vector3.UP * lift, rot))
    _assert_no_mismatches()
    assert_gt(_answers[true], MIN_EACH, "the cases attach (else only refusals are compared)")
    assert_gt(_answers[false], MIN_EACH, "and are refused")


# Bisect the game's answer from `from` (attached) along `step` (refused at its end) down to adjacent
# doubles, then ask the oracle both sides: it must put the refusal boundary in the same place.
func _boundary(label: String, part: Part, rot: Vector3, from: Vector3, step: Vector3) -> void:
    if not _action(part, from, rot)._attached() or _action(part, from + step, rot)._attached():
        _mismatches.append("%s: the game's answer does not change along the path" % label)
        return
    var lo := 0.0
    var hi := 1.0
    var mid := 0.5
    while mid > lo and mid < hi:
        if _action(part, from + step * mid, rot)._attached():
            lo = mid
        else:
            hi = mid
        mid = (lo + hi) * 0.5

    var near := _same(label + " last attached", _action(part, from + step * lo, rot))
    var far  := _same(label + " first refused", _action(part, from + step * hi, rot))
    if not near or far:
        _mismatches.append("%s: the oracle's refusal boundary is not the game's (t %.17f / %.17f)" % [label, lo, hi])


func test_lift_boundary_matches_oracle() -> void:
    var s := Vector3(100.0, _fixture.surface, 100.0)
    for part in _parts():
        for rot in _rotations():
            for anchor in [s, _open_ground()]:
                _boundary("%s rot %s lifted from %s" % [part.dimensions, rot, anchor], part, rot, anchor,
                    Vector3.UP * 6.0)
    _assert_no_mismatches()


# A part slid off a tall pillar at a height where the ground is out of reach: it attaches by its
# side, not by resting.
func test_side_boundary_matches_oracle() -> void:
    var ground := _open_ground()
    _store.stamp_box(ground + Vector3(0.0, 5.0, 0.0), Vector3(2.0, 10.0, 2.0), VoxelConstants.STORE_OP_UNION, 3, 0.5)
    var from := ground + Vector3.UP * 5.0
    for part in _parts():
        for rot in _rotations():
            for away in [Vector3(9.0, 0.0, 0.0), Vector3(6.0, 0.0, 6.0), Vector3(-2.0, 0.0, -8.0)]:
                _boundary("%s rot %s slid %s off the pillar" % [part.dimensions, rot, away], part, rot, from, away)
    _assert_no_mismatches()


# A lattice point exactly `reach` from a box, in the air, with one store value written at or below
# it: the tie on the reach (the point counts) and on the solid threshold (0.0 is not solid). Below
# it, barely solid, so a probe a millimetre off the cell below reads air.
func _tie_case(label: String, at: Vector3i, write: Vector3i, value: float, expect: bool) -> void:
    var reach := VoxelConstants.RENDER_BASE_CELL * sqrt(3.0) * 0.5
    var rod   := Part.new()
    rod.dimensions = Vector3(2.0 * (1.0 - reach), 0.1, 0.1)
    var action := _action(rod, Vector3(at) + Vector3(1.0, -0.05, 0.0), Vector3.ZERO)
    var brush  := action._xform()
    assert_eq(action._shape().sdf(brush.affine_inverse() * Vector3(at)), reach,
        "%s: the point is exactly reach from the brush" % label)
    var edits: Array[LatticeEdit] = [LatticeEdit.new(write, value)]
    Oracle.work(_store, edits).write(_store, PackedByteArray())
    assert_eq(_same(label, _action(rod, Vector3(at) + Vector3(1.0, -0.05, 0.0), Vector3.ZERO)), expect,
        "%s: the oracle attaches = %s" % [label, expect])


func test_exact_ties_match_oracle() -> void:
    var high := Vector3i(_open_ground()) + Vector3i(0, 12, 0)
    var cases := [
        ["solid at the point exactly reach away", Vector3i.ZERO, -1.0, true],
        ["exactly the threshold there", Vector3i.ZERO, VoxelConstants.SDF_SOLID_THRESHOLD, false],
        ["barely solid one cell below it", Vector3i.DOWN, -1e-4, true],
        ["barely solid one cell below the point inside", Vector3i(1, -1, 0), -1e-4, true],
        ["solid two cells below it", Vector3i(0, -2, 0), -1.0, false],
        ["solid one cell beyond it", Vector3i.LEFT, -1.0, false],
    ]
    for i in cases.size():
        var at := high + Vector3i(0, 5 * i, 0)   # stacked: the ground climbs steeply sideways
        _tie_case(cases[i][0], at, at + cases[i][1], cases[i][2], cases[i][3])
    _assert_no_mismatches()
