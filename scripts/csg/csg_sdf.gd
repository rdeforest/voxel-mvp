class_name CsgSdf

# Analytic signed-distance functions for the CSG editing primitives, in the
# shape's LOCAL frame (centred at the origin, axis-aligned). Negative = inside
# solid, positive = air — the same convention as the terrain SDF
# (VoxelConstants.SDF_SOLID_THRESHOLD), so a stamp combines with terrain by
# min() (union) / max(-d) (subtraction).
#
# Rotation and translation are the caller's job: transform the world query point
# into this local frame (point_local = basis.inverse() * (point - origin)) before
# evaluating. A pure-rotation basis is distance-preserving, so the value returned
# here IS the world signed distance.

enum Shape { BOX, CYLINDER, SPHERE }


# Box of full size `size`, centred at the origin. Exact distance (iquilezles):
# negative inside, positive outside.
static func box(p: Vector3, size: Vector3) -> float:
    var q := p.abs() - size * 0.5
    var outside := q.max(Vector3.ZERO).length()
    var inside  := minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
    return outside + inside


# Cylinder along local Y: `radius` around the Y axis, total height `height`.
static func cylinder(p: Vector3, radius: float, height: float) -> float:
    var radial := Vector2(p.x, p.z).length() - radius
    var axial  := absf(p.y) - height * 0.5
    var outside := Vector2(maxf(radial, 0.0), maxf(axial, 0.0)).length()
    var inside  := minf(maxf(radial, axial), 0.0)
    return outside + inside


static func sphere(p: Vector3, radius: float) -> float:
    return p.length() - radius
