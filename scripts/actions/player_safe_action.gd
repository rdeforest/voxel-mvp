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


# What a write does to the player. BURIES wins over DROPS: a buried player can't be caught by
# flying alone, since flight still collides.
enum Danger { NONE, DROPS, BURIES }


# The one refusal test, asked of the field an edit writes (its SdfLattice, the array handed to
# EditStore.write_region): does it turn any point of the capsule solid (bury the player) or any
# point of the support box air (drop them)? Read from the written field, not from which cell
# centres flip, so a part or brush thinner than a cell cannot slip past it. A null lattice (an
# edit that writes nothing) endangers no one.
func endangered_by(lattice: SdfLattice, store: EditStore) -> bool:
    return danger_of(lattice, store) != Danger.NONE


# endangered_by's test, saying which danger: what an instrument write, which bypasses the refusal,
# must rescue the player from.
func danger_of(lattice: SdfLattice, store: EditStore) -> Danger:
    if player == null or lattice == null or store == null:
        return Danger.NONE

    var at := player.global_position
    if lattice.solidifies_in(store, capsule_box(at)):
        return Danger.BURIES
    if lattice.empties_in(store, support_box(at)):
        return Danger.DROPS
    return Danger.NONE
