class_name AdditiveAction
extends PlayerSafeAction

# Verbs that place solid voxels. Two shared concerns live here so the individual verbs
# don't reinvent them: they can bury the player (PlayerSafeAction), and whatever they
# add takes the player's CURRENT material — nothing about adding terrain is
# material-specific, so the material choice belongs here once, not per verb. Each verb
# paints it into the store; subscribers to its matter-changed event read it back from there.

var material_name: StringName = &"Stone"
