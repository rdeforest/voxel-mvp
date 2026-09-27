extends Node

# The World scene root as a save sees it (WorldSnapshot): a StructuralIntegrity and a Player child,
# and the PartIndex behind part_index(). The caller adds it to the tree, which readies the
# integrity's TerrainSupport.
# (Drafted by Claude, overnight 2026-09-27.)

class PlayerStub:
    extends CharacterBody3D

    var build_state       := BuildState.new()
    var tool_index        := 2
    var _activity_indices: Array[int] = [1, 0, 3]


    func _init() -> void:
        var head := Node3D.new()
        head.name = "Head"
        add_child(head)


var index := PartIndex.new()


func _init() -> void:
    var integrity := StructuralIntegrity.new()
    var player    := PlayerStub.new()
    integrity.name = "StructuralIntegrity"
    player.name    = "Player"
    add_child(integrity)
    add_child(player)


func part_index() -> PartIndex:
    return index
