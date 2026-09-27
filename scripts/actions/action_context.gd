class_name ActionContext
extends RefCounted

# The shared world-context every Action needs. Built once by ActionFactories and
# handed to each Action so constructors carry only their own intent params, not
# the same collaborators repeated everywhere. `source` is who the edits it makes are credited to:
# the player's context says PLAYER; a replay runner or an instrument builds its own.

var store:     EditStore
var player:    CharacterBody3D
var integrity: StructuralIntegrity
var source:    EditSource.Kind


func _init(
    p_store:     EditStore,
    p_player:    CharacterBody3D,
    p_integrity: StructuralIntegrity,
    p_source:    EditSource.Kind = EditSource.Kind.PLAYER,
) -> void:
    store     = p_store
    player    = p_player
    integrity = p_integrity
    source    = p_source
