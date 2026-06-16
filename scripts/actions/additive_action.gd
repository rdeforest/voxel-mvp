class_name AdditiveAction
extends PlayerSafeAction

# Verbs that place solid voxels. Two shared concerns live here so the individual verbs
# don't reinvent them: they can bury the player (PlayerSafeAction), and whatever they
# add takes the player's CURRENT material — nothing about adding terrain is
# material-specific, so the material tagging belongs here once, not per verb.

var material_name: StringName = &"Stone"


# Tag the given newly-solid cells with the current material on the bus.
func emit_added(cells: Array) -> void:
    var mat := Materials.from_name(material_name)
    for cell in cells:
        VoxelEventBusSingleton.emit(
            VoxelAddedEvent.CHANNEL,
            VoxelAddedEvent.new(VoxelConstants.GRID_ID, cell, mat))
