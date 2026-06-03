class_name SdfShapes
extends RefCounted

# Analytic signed-distance fields for exercising the DC mesher. Negative inside.
# Shared by the tests and the preview so both contour the same definitions.

static func sphere(p: Vector3, r: float) -> float:
    return p.length() - r

# Exact box SDF (Inigo Quilez). Sharp faces, 90° edges, 3-plane corners — the
# crease test for Dual Contouring.
static func box(p: Vector3, b: Vector3) -> float:
    var q := p.abs() - b
    var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
    var inside  := minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
    return outside + inside

# A box with one corner sliced off by a diagonal plane, giving a non-axis-
# aligned crease where the cut meets the remaining faces.
static func wedge(p: Vector3, b: Vector3) -> float:
    var n := Vector3(1, 1, 0).normalized()
    return maxf(box(p, b), p.dot(n) - b.x * 0.5)
