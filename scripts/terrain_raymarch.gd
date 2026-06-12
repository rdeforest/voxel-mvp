class_name TerrainRaymarch

# Sphere-trace a ray through the EditStore SDF to a sub-metre-precise surface hit. Used for player
# aim (the cooked collision mesh is only ~1m, so a physics raycast quantizes the aim — fatal for
# placing sub-metre parts). Fixed fine steps so a sub-metre feature is never stepped over, then a
# bisection of the air->solid crossing for the precise surface point; the normal is the SDF
# gradient there. Pure + static so it's unit-testable against an analytic field.

# Returns {hit: bool, position: Vector3, normal: Vector3}. `step` should be <= the render cell so
# features aren't skipped; `reach` is the max ray distance.
static func surface(store: EditStore, origin: Vector3, dir: Vector3, reach: float, step: float) -> Dictionary:
    var miss := {"hit": false, "position": Vector3.ZERO, "normal": Vector3.UP}
    if store == null:
        return miss
    if store.sample(origin) < VoxelConstants.SDF_SOLID_THRESHOLD:
        return miss   # camera inside solid — nothing to target
    var t := step
    var prev_t := 0.0
    while t <= reach:
        if store.sample(origin + dir * t) < VoxelConstants.SDF_SOLID_THRESHOLD:
            var lo := prev_t   # last air
            var hi := t        # first solid
            for _i in 16:
                var mid := (lo + hi) * 0.5
                if store.sample(origin + dir * mid) < VoxelConstants.SDF_SOLID_THRESHOLD:
                    hi = mid
                else:
                    lo = mid
            var hp := origin + dir * hi
            return {"hit": true, "position": hp, "normal": _normal(store, hp)}
        prev_t = t
        t += step
    return miss

static func _normal(store: EditStore, p: Vector3) -> Vector3:
    var h := VoxelConstants.RENDER_BASE_CELL
    var g := Vector3(
        store.sample(p + Vector3(h, 0, 0)) - store.sample(p - Vector3(h, 0, 0)),
        store.sample(p + Vector3(0, h, 0)) - store.sample(p - Vector3(0, h, 0)),
        store.sample(p + Vector3(0, 0, h)) - store.sample(p - Vector3(0, 0, h)))
    return g.normalized() if g.length_squared() > 1e-12 else Vector3.UP
