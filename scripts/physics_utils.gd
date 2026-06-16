class_name PhysicsUtils

# Shared physics-space helpers. freeze_bodies_in is the guard FillAction and CsgAction both
# need: freeze any RigidBody3D overlapping an about-to-land SDF edit so physics doesn't squirt
# it sideways from the overlap on the next tick (the buried-body classifier reintegrates it).

const MAX_FROZEN_BODIES := 32   # intersect_shape result cap; an edit spanning more bodies won't freeze the rest

static func freeze_bodies_in(space: PhysicsDirectSpaceState3D, shape: Shape3D, xform: Transform3D) -> void:
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape              = shape
    query.transform          = xform
    query.collide_with_areas = false
    for hit in space.intersect_shape(query, MAX_FROZEN_BODIES):
        var body := hit.collider as RigidBody3D
        if body != null and not body.freeze:
            body.freeze = true
