extends GutTest

# CsgAction's intent, pinned headlessly: the computed work (via preview) must classify cells
# correctly from the analytic shape SDF combined with the existing field. The field is the
# EditStore, which defers to the procedural generator — so we stamp well ABOVE the generated
# surface, where the field reads as air, and a UNION actually creates solid (a SUBTRACT there
# is a no-op).

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

var _store:  EditStore
var _center: Vector3


func before_each() -> void:
    var surface := SparseVoxelOctree.terrain_surface(0.0, 0.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    _center = Vector3(0.0, surface + 60.0, 0.0)   # well into the air
    _store = EditStore.new()
    _store.setup(_center - Vector3.ONE * 128.0, 256.0, BASE, AMP, PERIOD, OCTAVES, SEED)


func _sphere(op: int, radius: float) -> CsgAction:
    return CsgAction.new(
        CsgSphereShape.new(radius),
        Transform3D(Basis.IDENTITY, _center), op, &"Stone", _store, null)


func test_sphere_add_marks_interior_solid() -> void:
    var action := _sphere(CsgState.Op.ADD, 4.0)
    assert_true(action.validate(), "stamp in empty air is valid")
    var preview := action.preview()
    var center_cell := Vector3i(_center.round())
    assert_false(preview.refused, "not refused")
    assert_true(preview.solid.has(center_cell),                     "centre becomes solid")
    assert_true(preview.solid.has(center_cell + Vector3i(3, 0, 0)), "inside the radius becomes solid")
    assert_false(preview.solid.has(center_cell + Vector3i(6, 0, 0)), "outside the radius stays air")
    assert_true(preview.air.is_empty(), "nothing was solid to remove (air terrain)")


func test_subtract_on_air_is_refused() -> void:
    # max(existing_air, -d) never drops below the air baseline -> no work -> refused.
    var carve := _sphere(CsgState.Op.SUBTRACT, 3.0)
    assert_false(carve.validate(), "carving empty air does nothing")
    assert_true(carve.preview().refused, "preview reflects the refusal")


func test_player_clearance_refuses_burying_stamp() -> void:
    # A solid stamp centred on the player must refuse (don't-deform-the-player).
    var player := CharacterBody3D.new()
    add_child_autofree(player)
    player.global_position = _center
    var action := CsgAction.new(
        CsgSphereShape.new(4.0),
        Transform3D(Basis.IDENTITY, _center), CsgState.Op.ADD, &"Stone", _store, player)
    assert_false(action.validate(), "stamp would bury the player -> refused")


func test_world_box_grows_with_rotation() -> void:
    # The touched AABB must enclose the rotated shape plus margin, so the surface
    # band is written on every side.
    var basis  := Basis(Vector3.UP, deg_to_rad(45.0))
    var action := CsgAction.new(
        CsgBoxShape.new(Vector3(4, 4, 4)),
        Transform3D(basis, Vector3(10, 0, 0)), CsgState.Op.ADD, &"Stone", _store, null)
    var box := action._world_box()
    # 4×4×4 box rotated 45° about Y spans ~5.66 in X/Z; +/- MARGIN(2) each side.
    assert_true(box.has_point(Vector3(10, 0, 0)), "encloses the centre")
    assert_gt(box.size.x, 5.66, "X spans the rotated diagonal plus margin")
