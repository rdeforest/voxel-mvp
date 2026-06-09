extends GutTest

# PlayerSafeAction is the single source of truth for the two danger volumes every
# near-player terrain edit checks against: the capsule (becoming solid here buries the
# player) and the support box just below the feet (becoming air here drops them through
# the world). These are the boxes that used to be copy-pasted into four action files;
# this guards their extents and — critically — that they're DISJOINT in the way the
# bury/drop distinction relies on (a feet-support cell is not a body cell, and vice
# versa), which is what makes LowerAction's new drop-check meaningful.

const ORIGIN := Vector3.ZERO

# A point at the player's torso, and one in the cell just below their feet.
const TORSO := Vector3(0.0, 0.0, 0.0)
const BELOW_FEET := Vector3(0.0, -2.0, 0.0)


func test_capsule_holds_the_body_not_the_feet_support() -> void:
    var capsule := PlayerSafeAction.capsule_box(ORIGIN)
    assert_true(capsule.has_point(TORSO), "the body box contains the torso")
    assert_false(capsule.has_point(BELOW_FEET), "the body box does NOT reach below the feet")


func test_support_box_holds_below_feet_not_the_body() -> void:
    var support := PlayerSafeAction.support_box(ORIGIN)
    assert_true(support.has_point(BELOW_FEET), "the support box contains the cell under the feet")
    assert_false(support.has_point(TORSO), "the support box does NOT reach up into the body")


func test_boxes_track_the_player() -> void:
    # Both volumes are relative to the player position, so a moved player moves them.
    var p := Vector3(100.0, 50.0, -30.0)
    assert_true(PlayerSafeAction.capsule_box(p).has_point(p + TORSO))
    assert_true(PlayerSafeAction.support_box(p).has_point(p + BELOW_FEET))
    assert_false(PlayerSafeAction.capsule_box(p).has_point(TORSO), "boxes don't stay at the origin")
