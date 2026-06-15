extends GutTest

# Reproduce the report: a sharp box < ~10 m away changes shape as you orbit it
# horizontally, and doesn't match the box you stamped. Hypothesis: the geomorph
# blend (Clipmap::value) mixes LOD0 with 2 m-downsampled LOD1 data by a factor that
# depends on distance-from-camera, so the SAME box meshes differently from different
# camera positions and deviates from the analytic surface in the blend band.
#
# Build the box's field analytically at LOD0 (cell 1) and LOD1 (cell 2), mesh with the
# clipmap centred at different "player" spots, and measure how far the vertices stray
# from the true box and whether the mesh changes with the centre.

const DIM   := 33
const DEPTH := 5
const BOX_C := Vector3(16, 16, 16)
const BOX_D := Vector3(3, 14, 4)


func _box(p: Vector3) -> float:
    return CsgSdf.box(p - BOX_C, BOX_D)

func _level(cell: float) -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                data[i] = _box(Vector3(x, y, z) * cell)
                i += 1
    return data

# Mesh the box with the clipmap centred at `center` (the "player"), geomorph active,
# no error collapse (dceps is irrelevant to the bug).
func _mesh(center: Vector3) -> PackedVector3Array:
    var arrays := DCOctreeMesher.new().mesh_clipmap(
        [_level(1.0), _level(2.0)], DIM,
        PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
        PackedFloat32Array([1.0, 2.0]),
        center, 16.0, DEPTH)        # half0 = 16 -> level0 covers d<=16, blends 8..16
    return arrays[Mesh.ARRAY_VERTEX]

# Max distance any vertex sits off the true analytic box surface.
func _max_dev(verts: PackedVector3Array) -> float:
    var worst := 0.0
    for v in verts:
        worst = maxf(worst, absf(_box(v)))
    return worst

# How much two meshes of the SAME box differ (nearest-vertex Hausdorff-ish).
func _divergence(a: PackedVector3Array, b: PackedVector3Array) -> float:
    var worst := 0.0
    for v in a:
        var nearest := 1e9
        for w in b:
            nearest = minf(nearest, v.distance_to(w))
        worst = maxf(worst, nearest)
    return worst


# Same box with error-driven collapse ON (the in-game default), but vary the CAMERA while
# the clipmap centre (the data) is held fixed. Under necessity-driven LOD the collapse keys
# on a fixed world-residual, not the camera, so the mesh must not move with the viewpoint.
func _mesh_collapse(camera: Vector3, tol: float) -> PackedVector3Array:
    var arrays := DCOctreeMesher.new().mesh_clipmap(
        [_level(1.0), _level(2.0)], DIM,
        PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
        PackedFloat32Array([1.0, 2.0]),
        BOX_C, 16.0, DEPTH,                       # clipmap centre fixed on the box
        camera, 771.0, tol, true, Vector3i())     # only the camera (+ proj, vestigial) varies
    return arrays[Mesh.ARRAY_VERTEX]

func test_collapse_is_camera_independent() -> void:
    # Near vs far camera over the SAME field: necessity LOD must mesh them identically.
    # (The old proj/dist metric coarsened the far view, so this caught the regression.)
    var near := _mesh_collapse(BOX_C + Vector3(12, 0, 0), 0.5)
    var far  := _mesh_collapse(BOX_C + Vector3(600, 0, 0), 0.5)
    gut.p("camera-indep: near_verts=%d far_verts=%d divergence=%.4f" % [
        near.size(), far.size(), _divergence(near, far)])
    assert_eq(near.size(), far.size(), "vertex count is camera-independent (necessity LOD)")
    assert_lt(_divergence(near, far), 1e-4, "mesh is identical from near and far cameras")


func test_box_mesh_is_view_dependent() -> void:
    # Player ON the box (everything d<8 -> pure LOD0, no blend): the control.
    var pure := _mesh(BOX_C)
    # Player ~10 m east / north: the box sits in the 8..16 geomorph band.
    var east := _mesh(BOX_C + Vector3(10, 0, 0))
    var north := _mesh(BOX_C + Vector3(0, 0, 10))

    gut.p("max_dev  pure=%.3f  east=%.3f  north=%.3f" % [_max_dev(pure), _max_dev(east), _max_dev(north)])
    gut.p("divergence east-vs-north = %.3f m" % _divergence(east, north))

    # Regression guard for the geomorph close-range fix (keep level 0 pure): the box
    # within the fine band must mesh the SAME from every angle. The ~0.5 m deviation
    # that remains is the separate 1 m-resolution sharpness limit on a 3-wide box
    # (one vertex per cell can't pin a sharp edge sub-cell) — Phase B, not this bug.
    assert_lt(_max_dev(pure), 0.6, "pure LOD0 hugs the analytic box (within 1 m-cell limit)")
    assert_lt(_max_dev(east), 0.6, "box stays on-surface when viewed from 10 m east")
    assert_lt(_divergence(east, north), 0.05, "box mesh is view-INDEPENDENT (east == north)")
