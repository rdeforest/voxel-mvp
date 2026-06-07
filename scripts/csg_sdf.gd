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


# Evaluate `shape` at local point `p` from a generic dimensions vector:
#   BOX      — full sizes (x, y, z)
#   CYLINDER — dims.x = radius, dims.y = height
#   SPHERE   — dims.x = radius
static func distance(shape: int, p: Vector3, dims: Vector3) -> float:
    match shape:
        Shape.BOX:      return box(p, dims)
        Shape.CYLINDER: return cylinder(p, dims.x, dims.y)
        Shape.SPHERE:   return sphere(p, dims.x)
    return 1.0


# Local-space AABB enclosing the shape (centred at the origin).
static func local_aabb(shape: int, dims: Vector3) -> AABB:
    match shape:
        Shape.BOX:
            return AABB(-dims * 0.5, dims)
        Shape.CYLINDER:
            var r := dims.x
            var h := dims.y
            return AABB(Vector3(-r, -h * 0.5, -r), Vector3(r * 2.0, h, r * 2.0))
        Shape.SPHERE:
            var rs := dims.x
            return AABB(-Vector3.ONE * rs, Vector3.ONE * rs * 2.0)
    return AABB()
