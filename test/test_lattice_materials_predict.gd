extends GutTest

# Gate for the per-leaf material an edit writes, which the game paints in EditStore (C++,
# lattice_materials, from the `made` mask the brush builder records) on every fill, dig, CSG stamp
# and part placement: it must be the GDScript original's (the oracle, test/support/lattice_oracle.gd)
# byte for byte — for the sphere stamp and every imprint shape, size and rotation, both ops, painted
# with several materials (Natural and a carve's -1 among them) and both air rules, on the store
# test_edit_store_predict gates on (test/support/predict_store.gd). The max-face seams are gated in
# test_lattice_materials.
#
# The C++ leaves out the oracle's second clause ("or the owner leaf held air there"): a point the
# write turns from air to solid is one the brush is solid at, since the builder combines exactly
# that brush with exactly that "before" — so this gate is what shows the two rules agree. One
# change to the C++ passes it and no gate could catch: testing the write's solidity at double
# instead of at the stored float32. They differ only for a value within ~1e-45 of zero, and every
# brush and store value is a difference of O(1) numbers, zero or at least an ulp of them.
# (Drafted by Claude, overnight 2026-09-26.)

const Oracle       := preload("res://test/support/lattice_oracle.gd")
const PredictStore := preload("res://test/support/predict_store.gd")

const PAINTS := [1, 4, 5, 3, 0]   # Stone, Wood, Metal, Sand (the history's box holds it), Natural
const MIN_EACH := 500             # leaves of each kind across a test's cases

var _fixture:    PredictStore
var _store:      EditStore
var _mismatches: Array[String] = []
var _painted:    int           = 0
var _kept_solid: int           = 0
var _kept_air:   int           = 0
var _cases:      int           = 0


func before_each() -> void:
    _fixture    = PredictStore.new()
    _store      = _fixture.store
    _mismatches.clear()
    _painted    = 0
    _kept_solid = 0
    _kept_air   = 0
    _cases      = 0


# Each lattice is painted twice: with a material from PAINTS under one air rule, and as a carve
# (-1, which never repaints: UNION lattices included, though no caller asks that) under the other.
func _same(label: String, lat: SdfLattice, brush_solid: Callable) -> void:
    var material: int = PAINTS[_cases % PAINTS.size()]
    var keeps := _cases % 2 == 0
    _cases += 1
    for run in [[material, keeps], [-1, not keeps]]:
        var want := Oracle.materials(lat, _store, run[0], brush_solid, run[1])
        var got  := lat.materials(_store, run[0], run[1])
        if got != want:
            _mismatches.append("%s material %d keeps %s: %s" % [label, run[0], run[1], _first_difference(got, want)])
        _tally(lat, want, run[0])


func _first_difference(got: PackedByteArray, want: PackedByteArray) -> String:
    if got.size() != want.size():
        return "size %d vs %d" % [got.size(), want.size()]
    for i in want.size():
        if got[i] != want[i]:
            return "index %d: %d vs %d" % [i, got[i], want[i]]
    return "?"


# Leaves painted with the edit's material where the store held another, and leaves keeping a
# nonzero material with and without a solid corner: the three ways a leaf's entry is decided.
func _tally(lat: SdfLattice, want: PackedByteArray, material: int) -> void:
    var half := Vector3.ONE * (lat.cell * 0.5)
    for z in lat.dim - 1:
        for y in lat.dim - 1:
            for x in lat.dim - 1:
                var i    := Vector3i(x, y, z)
                var held := _store.material_at(lat.point(i) + half)
                var got  := want[lat.index(i)]
                if got == material and got != held:
                    _painted += 1
                elif got == held and held != 0:
                    if _any_solid_corner(lat, i):
                        _kept_solid += 1
                    else:
                        _kept_air += 1


func _any_solid_corner(lat: SdfLattice, i: Vector3i) -> bool:
    for k in 8:
        if lat.sdf[lat.index(i + Vector3i(CubeGeometry.corner(k)))] < VoxelConstants.SDF_SOLID_THRESHOLD:
            return true
    return false


func _assert_all_same() -> void:
    assert_eq(_mismatches.size(), 0, "the game matches the oracle byte for byte:\n" + "\n".join(_mismatches.slice(0, 10)))
    assert_gt(_painted, MIN_EACH, "the cases paint leaves (else painting is compared all-unpainted)")
    assert_gt(_kept_solid, MIN_EACH, "and keep solid leaves' materials")
    assert_gt(_kept_air, MIN_EACH, "and keep air leaves' materials under air_keeps")


func test_sphere_stamp_materials_match_oracle() -> void:
    for p in _fixture.positions():
        for radius: float in [1.0, 1.5, 2.5, 3.7]:
            for op in [VoxelConstants.STORE_OP_UNION, VoxelConstants.STORE_OP_SUBTRACT]:
                var lat := SdfLattice.sphere_stamp(_store, p, radius, op, VoxelConstants.RENDER_BASE_CELL)
                _same("sphere %s r%s op%d" % [p, radius, op], lat,
                    func(c: Vector3) -> bool: return c.distance_to(p) < radius)
    _assert_all_same()


# Sizes from a sub-cell plank (a part thinner than a cell) to a 12 m box.
func _shapes() -> Array[CsgShape]:
    return [
        CsgBoxShape.new(Vector3(4.0, 4.0, 4.0)),
        CsgBoxShape.new(Vector3(3.0, 0.2, 0.7)),
        CsgBoxShape.new(Vector3(12.0, 3.0, 7.0)),
        CsgCylinderShape.new(2.0, 5.0),
        CsgCylinderShape.new(0.7, 3.3),
        CsgSphereShape.new(3.0),
        CsgSphereShape.new(1.3),
    ]


# Each shape at each position unrotated and under one of the turns, cycling (the oracle is slow).
func _bases(turn: int) -> Array[Basis]:
    var turns: Array[Basis] = [
        Basis(Vector3.UP, PI * 0.25),
        Basis(Vector3(0.3, 1.0, 0.2).normalized(), 0.7),
        Basis.from_euler(Vector3(deg_to_rad(90.0), 0.0, 0.0)),
    ]
    return [Basis(), turns[turn % turns.size()]]


func test_imprint_materials_match_oracle() -> void:
    var turn := 0
    for shape in _shapes():
        for p in _fixture.positions():
            turn += 1
            for basis in _bases(turn):
                var xform   := Transform3D(basis, p)
                var inverse := xform.affine_inverse()
                for op in [CsgState.Op.ADD, CsgState.Op.SUBTRACT]:
                    _same("imprint %s %s at %s op%d" % [shape.sdf_kind(), shape.sdf_dims(), xform, op],
                        VoxelImprint.lattice(_store, shape, xform, op),
                        func(c: Vector3) -> bool: return shape.sdf(inverse * c) < VoxelConstants.SDF_SOLID_THRESHOLD)
    _assert_all_same()


# A lattice from any builder but the brush ones has no `made` mask to paint from: refused, not
# painted as if nothing were made.
func test_lattice_without_made_is_refused() -> void:
    var edits: Array[LatticeEdit] = [LatticeEdit.new(Vector3i(_fixture.base), -1.0)]
    var lat := StoreWrite.lattice(_store, edits)
    assert_eq(lat.made.size(), 0, "a work lattice carries no made mask")
    assert_eq(lat.materials(_store, 1, true).size(), 0, "painting it is refused")
    assert_engine_error("made must hold dim^3 values")
