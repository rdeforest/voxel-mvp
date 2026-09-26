extends GutTest

# EmptyVoxel and Fill ask PlayerSafeAction.endangered_by of the field they actually write, like
# the other near-player edits, instead of no check (EmptyVoxel) or a distance rule of their own
# (Fill). Dig refuses the carve its ghost refuses. On the game's store (EditStoreManager's
# generator and root), with a real body in the tree for the player.

const COLUMN := Vector2(100.0, 100.0)

# FillAction's retired rule refused within this distance of the brush's surface.
const OLD_FILL_CLEARANCE := 1.0

var _store:   EditStore
var _surface: float


func before_each() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store   = manager.store
    _surface = EditStore.terrain_surface(COLUMN.x, COLUMN.y, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


func _body(at: Vector3) -> CharacterBody3D:
    var body := CharacterBody3D.new()
    add_child_autofree(body)
    body.global_position = at
    return body

func _ctx(player: CharacterBody3D = null) -> ActionContext:
    return ActionContext.new(_store, player, null)

# Where a player standing on the column's surface has their origin (the capsule's middle).
func _standing() -> Vector3:
    return Vector3(COLUMN.x + 0.5, _surface - _body_box().position.y, COLUMN.y + 0.5)

# The capsule box about a player at the origin.
func _body_box() -> AABB:
    return PlayerSafeAction.capsule_box(Vector3.ZERO)

# A lattice-aligned point well above the terrain, so every brush there starts in open air.
func _sky() -> Vector3:
    return Vector3(COLUMN.x, floorf(_surface) + 30.0, COLUMN.y)


# --- EmptyVoxel ---

# The topmost solid cell of the column that EmptyVoxel can empty with nobody around.
func _emptiable_surface_cell() -> Vector3i:
    for y in range(floori(_surface), floori(_surface) - 4, -1):
        var cell := Vector3i(int(COLUMN.x), y, int(COLUMN.y))
        if EmptyVoxelAction.new(cell, _ctx()).validate():
            return cell
    return Vector3i.MAX


func test_empty_voxel_refuses_the_cell_the_player_stands_on() -> void:
    var cell := _emptiable_surface_cell()
    assert_ne(cell, Vector3i.MAX, "some cell under the surface can be emptied with nobody near")
    var standing := _standing()
    assert_true(PlayerSafeAction.support_box(standing).has_point(VoxelUtils.sample_point(cell)),
        "the cell is under the player's feet")

    var action := EmptyVoxelAction.new(cell, _ctx(_body(standing)))
    assert_false(action.validate(), "emptying the cell under the player would drop them -> refused")
    assert_true(action.preview().refused, "the ghost shows the refusal")

func test_empty_voxel_allows_the_same_cell_with_the_player_elsewhere() -> void:
    var cell := _emptiable_surface_cell()
    var away := _standing() + Vector3(10.0, 0.0, 0.0)
    assert_true(EmptyVoxelAction.new(cell, _ctx(_body(away))).validate(),
        "the refusal is about the player, not the cell")


# --- Fill ---

# A brush whose bottom dips 0.3 m into the top of the player's head. The retired distance rule
# let it through (the brush's surface is 1.2 m from the player's origin); the written field
# turns the top of the capsule solid.
func test_fill_refuses_a_brush_that_buries_the_head_the_old_distance_rule_allowed() -> void:
    var player := _sky() + Vector3(0.0, 0.5, 0.0)
    var head   := PlayerSafeAction.capsule_box(player).end.y
    var radius := 2.0
    var center := Vector3(player.x, head - 0.3 + radius, player.z)
    assert_gt(player.distance_to(center), radius + OLD_FILL_CLEARANCE, "the old rule would have allowed it")

    var action := FillAction.new(center, radius, _ctx(_body(player)))
    assert_false(action.validate(), "the written field turns the top of the capsule solid -> refused")
    assert_true(action.preview().refused, "the ghost shows the refusal")

    var clear := FillAction.new(center + Vector3(0.0, 1.0, 0.0), radius, _ctx(_body(player)))
    assert_true(clear.validate(), "the same brush a metre higher misses the capsule")

# A brush wholly inside rock the player is standing against (a repaint). The retired distance
# rule refused it (the brush's surface is 0.9 m from the player's origin); the written field
# makes nothing solid that was air, so nothing is buried.
func test_fill_allows_a_repaint_beside_the_player_the_old_distance_rule_refused() -> void:
    var rock := _sky()
    FillAction.new(rock, 6.0, _ctx()).execute()
    var player := rock + Vector3(6.0 - _body_box().position.x, 0.0, 0.0)
    var radius := 2.0
    var center := rock + Vector3(3.7, 0.0, 0.0)
    assert_lte(player.distance_to(center), radius + OLD_FILL_CLEARANCE, "the old rule would have refused it")

    var action := FillAction.new(center, radius, _ctx(_body(player)), &"Wood")
    assert_true(action.validate(), "the written field buries nothing -> allowed")
    assert_false(action.preview().refused, "the ghost agrees")

    var reaching := FillAction.new(center + Vector3(1.5, 0.0, 0.0), radius, _ctx(_body(player)))
    assert_false(reaching.validate(), "a brush poking out of the rock into the capsule is refused")


# --- Dig ---

func test_dig_refuses_a_carve_that_changes_no_cell() -> void:
    var action := DigAction.new(_sky(), 3.0, _ctx())
    assert_false(action.validate(), "digging open air carves nothing -> refused")
    assert_true(action.preview().refused, "which is what the ghost already showed")
