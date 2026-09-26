class_name PlayerSafeAction
extends Action

# Common parent for terrain edits near the player. A player edit must never bury them
# (push solid into their body) nor drop them out of the world (carve the ground from
# under their feet). This is the single source of truth for those two danger volumes;
# subclasses ask `endangered_by()` of the field they write rather than re-deriving boxes.

var player: CharacterBody3D

# The player's body box and the support box just below the feet, sized for the
# ~0.5 m-radius, 3 m-tall capsule. The one place these extents live.
const _CAPSULE_MIN  := Vector3(-0.6, -1.5, -0.6)
const _CAPSULE_SIZE := Vector3(1.2, 3.0, 1.2)
const _SUPPORT_MIN  := Vector3(-0.6, -3.0, -0.6)
const _SUPPORT_SIZE := Vector3(1.2, 1.5, 1.2)


static func capsule_box(player_pos: Vector3) -> AABB:
    return AABB(player_pos + _CAPSULE_MIN, _CAPSULE_SIZE)

static func support_box(player_pos: Vector3) -> AABB:
    return AABB(player_pos + _SUPPORT_MIN, _SUPPORT_SIZE)


# The one refusal test, asked of the field an edit writes (its SdfLattice, the array handed to
# EditStore.write_region): does it turn any point of the capsule solid (bury the player) or any
# point of the support box air (drop them)? Read from the written field, not from which cell
# centres flip, so a part or brush thinner than a cell cannot slip past it. A null lattice (an
# edit that writes nothing) endangers no one.
func endangered_by(lattice: SdfLattice, store: EditStore) -> bool:
    if player == null or lattice == null or store == null:
        return false
    var at := player.global_position
    return lattice.solidifies_in(store, capsule_box(at)) or lattice.empties_in(store, support_box(at))
