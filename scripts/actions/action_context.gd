class_name ActionContext
extends RefCounted

# The shared world-context every Action needs. Built once by ActionFactories and
# handed to each Action so constructors carry only their own intent params, not
# the same collaborators repeated everywhere.

var store:     EditStore
var player:    CharacterBody3D
var integrity: StructuralIntegrity
var pbd:       PbdStructure


func _init(
    p_store:     EditStore,
    p_player:    CharacterBody3D,
    p_integrity: StructuralIntegrity,
    p_pbd:       PbdStructure,
) -> void:
    store     = p_store
    player    = p_player
    integrity = p_integrity
    pbd       = p_pbd
