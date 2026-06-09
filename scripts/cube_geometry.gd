class_name CubeGeometry

# Unit-cube corner + edge geometry shared by the debug/preview overlays (the GDScript
# twin of C++ voxel_dc::CB). Corners are indexed by xyz bits: 0=(0,0,0) .. 7=(1,1,1).

# The 12 edges as a wireframe loop order (bottom face, top face, verticals) — used for
# line-drawing, distinct from voxel_dc::EDGES which is axis-grouped for meshing.
const EDGES := [
    [0, 1], [1, 3], [3, 2], [2, 0],   # bottom face
    [4, 5], [5, 7], [7, 6], [6, 4],   # top face
    [0, 4], [1, 5], [2, 6], [3, 7],   # verticals
]


# Corner of the unit cube.
static func corner(i: int) -> Vector3:
    return Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))

# Corner pulled inward by `inset` on each axis (for outlines that avoid z-fighting).
static func corner_inset(i: int, inset: float) -> Vector3:
    return Vector3(
        inset if (i & 1) == 0 else 1.0 - inset,
        inset if ((i >> 1) & 1) == 0 else 1.0 - inset,
        inset if ((i >> 2) & 1) == 0 else 1.0 - inset)

# Corner of an arbitrary AABB (the unit corner scaled into the box).
static func corner_in(aabb: AABB, i: int) -> Vector3:
    return aabb.position + aabb.size * corner(i)
