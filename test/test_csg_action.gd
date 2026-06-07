extends GutTest

# A bare VoxelLodTerrain isn't editable (no stream/streaming), so set_voxel_f
# can't round-trip here — the actual write is the same vt.set_voxel_f path flatten
# and fill use in-game. What we CAN pin headlessly is the action's intent: the
# computed work (via preview) must classify cells correctly from the analytic SDF
# combined with the existing field (which reads as air everywhere on a bare node).

var _terrain: VoxelLodTerrain


func before_each() -> void:
    _terrain = VoxelLodTerrain.new()
    add_child_autofree(_terrain)


func _sphere(op: int, radius: float) -> CsgAction:
    return CsgAction.new(
        CsgSdf.Shape.SPHERE, Vector3(radius, 0, 0),
        Transform3D(Basis.IDENTITY, Vector3.ZERO), op, &"Stone", _terrain, null)


func test_sphere_add_marks_interior_solid() -> void:
    var action := _sphere(CsgState.Op.ADD, 4.0)
    assert_true(action.validate(), "stamp in empty air is valid")
    var p := action.preview()
    assert_false(p.refused, "not refused")
    assert_true(p.solid.has(Vector3i(0, 0, 0)),  "centre becomes solid")
    assert_true(p.solid.has(Vector3i(3, 0, 0)),  "inside the radius becomes solid")
    assert_false(p.solid.has(Vector3i(6, 0, 0)), "outside the radius stays air")
    assert_true(p.air.is_empty(), "nothing was solid to remove (air terrain)")


func test_subtract_on_air_is_refused() -> void:
    # max(existing_air, -d) never drops below the air baseline -> no work -> refused.
    var carve := _sphere(CsgState.Op.SUBTRACT, 3.0)
    assert_false(carve.validate(), "carving empty air does nothing")
    assert_true(carve.preview().refused, "preview reflects the refusal")


func test_player_clearance_refuses_burying_stamp() -> void:
    # A solid stamp centred on the player must refuse (don't-deform-the-player).
    var player := CharacterBody3D.new()
    add_child_autofree(player)
    player.global_position = Vector3.ZERO
    var action := CsgAction.new(
        CsgSdf.Shape.SPHERE, Vector3(4, 0, 0),
        Transform3D(Basis.IDENTITY, Vector3.ZERO), CsgState.Op.ADD, &"Stone", _terrain, player)
    assert_false(action.validate(), "stamp would bury the player -> refused")


func test_world_box_grows_with_rotation() -> void:
    # The touched AABB must enclose the rotated shape plus margin, so the surface
    # band is written on every side.
    var basis  := Basis(Vector3.UP, deg_to_rad(45.0))
    var action := CsgAction.new(
        CsgSdf.Shape.BOX, Vector3(4, 4, 4),
        Transform3D(basis, Vector3(10, 0, 0)), CsgState.Op.ADD, &"Stone", _terrain, null)
    var box := action._world_box()
    # 4×4×4 box rotated 45° about Y spans ~5.66 in X/Z; +/- MARGIN(2) each side.
    assert_true(box.has_point(Vector3(10, 0, 0)), "encloses the centre")
    assert_gt(box.size.x, 5.66, "X spans the rotated diagonal plus margin")
