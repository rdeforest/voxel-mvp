class_name Part
extends Schematic

# Outer bounding box of the Part in local space. The procedural mesh,
# collision, and footprint all derive from this. The Part is bottom-anchored:
# the box's local-space bottom face sits at Y=0.
@export var dimensions:    Vector3    = Vector3.ONE

@export var material_name: StringName = &"Wood"


# World transform for a part placed at placement_pos with the given rotation. The
# brush's local origin is the unrotated bottom-center; after rotation the bottom and
# horizontal centroid move off that origin, so we shift the origin to put the rotated
# bottom at placement_pos.y and the rotated centroid over placement_pos.x/.z. Single
# source for the ghost, the footprint, and the imprint placement.
func world_transform(basis: Basis, placement_pos: Vector3) -> Transform3D:
    var unrot   := AABB(Vector3(-dimensions.x * 0.5, 0.0, -dimensions.z * 0.5), dimensions)
    var rotated := Transform3D(basis, Vector3.ZERO) * unrot
    var shift   := Vector3(
        -(rotated.position.x + rotated.size.x * 0.5),
         -rotated.position.y,
        -(rotated.position.z + rotated.size.z * 0.5))
    return Transform3D(basis, placement_pos + shift)
