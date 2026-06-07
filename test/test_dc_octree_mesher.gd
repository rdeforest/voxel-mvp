extends GutTest

# The production C++ octree-DC mesher (DCOctreeMesher.mesh_clipmap), the meshing
# heart of DCTerrainManager. Two invariants on an analytic sphere:
#   - a single (uniform) clipmap level reproduces a watertight sphere — the
#     minimal-edge meshing machinery is correct.
#   - a fine-core / coarse-shell clipmap (two levels) still meshes watertight
#     across the LOD boundary — the crack-free transition that is the whole point
#     of the clipmap mesher, and the property no other test exercises.
#
# Watertight = closed 2-manifold: every edge shared by exactly two triangles. That
# one invariant catches both holes and cracks across the level transition.
#
# (Replaces the GDScript OctreeDC algorithm tests; the prototype mesher was retired
# once this C++ port became the production render path.)

const CENTER := Vector3(16, 16, 16)
const RADIUS := 10.0
const DEPTH  := 5                       # octree root [0, 32]^3
const DIM    := 33                      # corner samples per level (DEPTH^2 + 1)

func _sphere(p: Vector3) -> float:
    return p.distance_to(CENTER) - RADIUS

# Sample the sphere into one clipmap level's flat grid (x-fastest), matching the
# layout DCTerrainManager feeds: world = origin + lattice * cell.
func _level(origin: Vector3, cell: float) -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                data[i] = _sphere(origin + Vector3(x, y, z) * cell)
                i += 1
    return data


func _edge_audit(idx: PackedInt32Array) -> Dictionary:
    var counts := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
            var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[key] = counts.get(key, 0) + 1
    var boundary := 0
    var nonmanifold := 0
    for k in counts:
        if counts[k] == 1:   boundary += 1
        elif counts[k] > 2:  nonmanifold += 1
    return {"boundary": boundary, "nonmanifold": nonmanifold}

func _mesh(level_data: Array, origins: PackedVector3Array, cells: PackedFloat32Array, half0: float) -> Array:
    var arrays := DCOctreeMesher.new().mesh_clipmap(level_data, DIM, origins, cells, CENTER, half0, DEPTH)
    assert_false(arrays.is_empty(), "mesher produced a surface")
    return arrays

func _assert_watertight(arrays: Array, hug_tol: float, min_verts := 200) -> void:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    assert_gt(verts.size(), min_verts, "meaningfully tessellated")
    assert_eq(idx.size() % 3, 0)
    var audit := _edge_audit(idx)
    assert_eq(audit["boundary"], 0, "boundary edges (holes/cracks)")
    assert_eq(audit["nonmanifold"], 0, "non-manifold edges")
    var max_dev := 0.0
    for v in verts:
        max_dev = maxf(max_dev, absf(v.distance_to(CENTER) - RADIUS))
    assert_lt(max_dev, hug_tol, "vertices hug the sphere")


func test_uniform_level_is_watertight():
    # One level covering the whole root (half0 huge → every cell is level 0, size 1).
    var data := _level(Vector3.ZERO, 1.0)
    var arrays := _mesh([data], PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]), 1e9)
    _assert_watertight(arrays, 1.5)


func test_lod_transition_is_watertight():
    # Fine core (cell 1, |d| <= 8) + coarse shell (cell 2, 8 < |d| <= 16). The sphere
    # surface (Chebyshev radius ~5.8 .. 10) straddles the boundary, so the level
    # transition cuts across the surface — the crack-free stitch under test.
    var fine := _level(Vector3.ZERO, 1.0)                       # covers [0, 32]
    var coarse := _level(Vector3(-16, -16, -16), 2.0)           # covers [-16, 48]
    var arrays := _mesh(
        [fine, coarse],
        PackedVector3Array([Vector3.ZERO, Vector3(-16, -16, -16)]),
        PackedFloat32Array([1.0, 2.0]),
        8.0)
    _assert_watertight(arrays, 2.5)                             # coarse cells are size 2


# --- Error-driven LOD (bottom-up collapse) ---
#
# The redesign: build to the data floor, then collapse a node into one leaf wherever
# its ACCUMULATED QEF (the real fine Hermite data) is fit by one vertex within eps_px
# on screen, floored so a flat field stays >=2 cells/axis. Its spec is two invariants:
#   - error-mode stays watertight on the sphere (collapse + point-location stitching
#     introduce size jumps but no cracks),
#   - it coarsens a flat field far below distance-mode without holing it (the failure
#     of the old top-down metric, which collapsed a flat region to one empty cell).

const PROJ := 500.0   # stand-in viewport_height/(2 tan(fov/2))

func _mesh_err(level_data: Array, origins: PackedVector3Array, cells: PackedFloat32Array, half0: float,
        camera: Vector3, eps_px: float) -> Array:
    return DCOctreeMesher.new().mesh_clipmap(
        level_data, DIM, origins, cells, CENTER, half0, DEPTH, camera, PROJ, eps_px, true)

# A flat field: SDF = world.z - PLANE_Z (negative below, positive above). An OPEN
# surface — boundary edges at the octree perimeter are expected; what matters is it
# coarsens without a hole in the interior.
const PLANE_Z := 16.0
func _plane_level(origin: Vector3, cell: float) -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                data[i] = (origin + Vector3(x, y, z) * cell).z - PLANE_Z
                i += 1
    return data


func test_error_mode_sphere_watertight():
    # Camera far enough that the screen error of the sphere's curvature falls under eps,
    # so cells collapse — to varying sizes across the surface. Point-location meshing must
    # stitch those size jumps crack-free, exactly as it does the clipmap LOD boundary.
    var data := _level(Vector3.ZERO, 1.0)
    var origins := PackedVector3Array([Vector3.ZERO])
    var cells := PackedFloat32Array([1.0])
    var camera := CENTER + Vector3(0, 0, 220)
    var fine := _mesh([data], origins, cells, 1e9)                       # distance mode (baseline)
    var coarse := _mesh_err([data], origins, cells, 1e9, camera, 1.0)
    assert_false(coarse.is_empty(), "error mode produced a surface")
    _assert_watertight(coarse, 3.5, 40)                                # looser hug + lower floor — aggressive collapse, still closed
    var fine_tris: int   = (fine[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
    var coarse_tris: int = (coarse[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
    assert_lt(coarse_tris, fine_tris, "error mode coarsened the curved sphere")


func test_error_mode_coarsens_flat_without_holing():
    # A flat field is the case the old top-down metric broke (collapsed to one empty
    # cell -> a hole). Bottom-up collapse should coarsen it hard (a plane needs few
    # cells) yet still produce a connected surface that hugs the plane.
    var data := _plane_level(Vector3.ZERO, 1.0)
    var origins := PackedVector3Array([Vector3.ZERO])
    var cells := PackedFloat32Array([1.0])
    var fine := _mesh([data], origins, cells, 1e9)
    var coarse := _mesh_err([data], origins, cells, 1e9, CENTER + Vector3(0, 0, 60), 1.0)
    assert_false(coarse.is_empty(), "flat field still meshed (not holed to nothing)")
    var fine_tris: int   = (fine[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
    var coarse_tris: int = (coarse[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
    assert_lt(coarse_tris, fine_tris / 4, "flat field coarsened far below distance mode")
    assert_gt(coarse_tris, 0, "flat field kept a surface (min-grid floor, no full collapse)")
    var verts: PackedVector3Array = coarse[Mesh.ARRAY_VERTEX]
    var max_dev := 0.0
    for v in verts:
        max_dev = maxf(max_dev, absf(v.z - PLANE_Z))
    assert_lt(max_dev, 0.5, "coarse vertices still lie on the plane")


# --- Collapse hysteresis (persistent state, the anti-popping property) ---

func _err_tris(mesher: DCOctreeMesher, data: PackedFloat32Array, camera: Vector3, eps: float) -> int:
    var arrays := mesher.mesh_clipmap(
        [data], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        CENTER, 1e9, DEPTH, camera, PROJ, eps, true, Vector3i.ZERO)
    if arrays.is_empty():
        return 0
    return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3

func test_collapse_hysteresis_is_sticky():
    # The popping is a node oscillating collapsed<->subdivided as the camera moves. A
    # reused mesher remembers last frame's collapse and keeps a collapsed node collapsed
    # until its error clearly exceeds eps (×HYST=2.5). So: warm the persistent mesher far
    # away (collapsed), then mesh from half the distance (error ~2x, still inside the
    # 2.5x band) — it should STAY coarse, where a cold mesh at that distance refines.
    var data := _level(Vector3.ZERO, 1.0)
    var far := CENTER + Vector3(0, 0, 220)
    var near := CENTER + Vector3(0, 0, 110)            # factor 2 < HYST(2.5): inside the band

    var cold := DCOctreeMesher.new()
    var tris_far  := _err_tris(cold, data, far, 1.0)   # fresh, far
    var cold2 := DCOctreeMesher.new()
    var tris_near := _err_tris(cold2, data, near, 1.0) # fresh, near (no history)

    var warm := DCOctreeMesher.new()
    _err_tris(warm, data, far, 1.0)                    # warm the history at `far` (collapses)
    var tris_sticky := _err_tris(warm, data, near, 1.0)  # then move to `near` — should stick coarse

    assert_gt(tris_near, tris_far, "near genuinely refines more than far (the LOD differs)")
    assert_lt(tris_sticky, tris_near, "hysteresis kept it coarser than a cold mesh at the same spot")
    assert_lte(tris_sticky, tris_far + tris_far / 20, "stayed ~as coarse as the warmed (far) state")
