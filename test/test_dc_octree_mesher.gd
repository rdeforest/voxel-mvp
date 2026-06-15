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
# on screen (we*proj/dist), floored so a flat field stays >=2 cells/axis. Two invariants:
#   - error-mode stays watertight on the sphere (collapse + point-location stitching
#     introduce size jumps but no cracks),
#   - it coarsens a flat field far below no-collapse mode without holing it (the failure
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
    # The sphere's curvature collapses to varying cell sizes across the surface (necessity LOD,
    # tolerance 1.0). Point-location meshing must stitch those size jumps crack-free, exactly as
    # it does the clipmap LOD boundary.
    var data := _level(Vector3.ZERO, 1.0)
    var origins := PackedVector3Array([Vector3.ZERO])
    var cells := PackedFloat32Array([1.0])
    var camera := CENTER + Vector3(0, 0, 220)                            # far: curvature falls under eps
    var fine := _mesh([data], origins, cells, 1e9)                       # no-collapse baseline
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


# Screen-error LOD is collapse = f(field, camera): the same world residual projects to more
# pixels up close and through a narrow FOV, so the LOD responds to BOTH. This is the property
# Stage 1 restored (and the necessity code lacked — these asserts would fail on it).

func _err_tris(mesher: DCOctreeMesher, data: PackedFloat32Array, camera: Vector3, proj: float, eps: float) -> int:
    var arrays := mesher.mesh_clipmap(
        [data], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        CENTER, 1e9, DEPTH, camera, proj, eps, true, Vector3i.ZERO)
    if arrays.is_empty():
        return 0
    return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3

func test_screen_error_responds_to_distance_and_fov():
    var data := _level(Vector3.ZERO, 1.0)              # the sphere
    var far  := CENTER + Vector3(0, 0, 220)
    var near := CENTER + Vector3(0, 0, 80)
    var m := DCOctreeMesher.new()
    var tris_far  := _err_tris(m, data, far,  PROJ,       1.0)
    var tris_near := _err_tris(m, data, near, PROJ,       1.0)
    var tris_zoom := _err_tris(m, data, far,  PROJ * 4.0, 1.0)   # telescope from the far spot
    assert_gt(tris_near, tris_far, "closer camera keeps more detail (larger on-screen error)")
    assert_gt(tris_zoom, tris_far, "narrow FOV (telescope) refines distant terrain")


# Stage 2a: the retained octree re-walked at a new camera must EQUAL a from-scratch build at that
# camera. The tree + per-node QEFs are field-derived (camera-independent), so only the collapse pass
# differs — remesh() re-decides collapse on the cached tree without re-sampling the field. This is the
# invariant the whole persistent-octree movement path rests on.
func test_remesh_rewalk_equals_fresh_build():
    var data := _level(Vector3.ZERO, 1.0)
    var origins := PackedVector3Array([Vector3.ZERO])
    var cells := PackedFloat32Array([1.0])
    var far  := CENTER + Vector3(0, 0, 220)
    var near := CENTER + Vector3(0, 0, 80)

    var m := DCOctreeMesher.new()
    var built_far := m.mesh_clipmap([data], DIM, origins, cells, CENTER, 1e9, DEPTH, far, PROJ, 1.0, true)
    # Re-walk at the SAME camera reproduces the build exactly.
    var rewalk_far: Array = m.remesh(far, PROJ, 1.0)
    assert_eq(rewalk_far[Mesh.ARRAY_VERTEX], built_far[Mesh.ARRAY_VERTEX], "remesh at the build camera reproduces its vertices")
    assert_eq(rewalk_far[Mesh.ARRAY_INDEX],  built_far[Mesh.ARRAY_INDEX],  "...and its indices")

    # Re-walk at a NEARER camera equals a fresh build there — no field re-sample, identical result.
    var rewalk_near: Array = m.remesh(near, PROJ, 1.0)
    var fresh_near := DCOctreeMesher.new().mesh_clipmap([data], DIM, origins, cells, CENTER, 1e9, DEPTH, near, PROJ, 1.0, true)
    assert_eq(rewalk_near[Mesh.ARRAY_VERTEX], fresh_near[Mesh.ARRAY_VERTEX], "re-walk at a new camera equals a fresh build there")
    assert_eq(rewalk_near[Mesh.ARRAY_INDEX],  fresh_near[Mesh.ARRAY_INDEX],  "...indices too")
    assert_gt((rewalk_near[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),
              (rewalk_far[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),
              "the nearer re-walk kept more detail (collapse re-decided, not re-sampled)")

func test_remesh_without_build_is_empty():
    assert_true((DCOctreeMesher.new().remesh(Vector3.ZERO, 500.0, 1.0) as Array).is_empty(),
        "remesh with no retained build returns empty, not a crash")


# --- Material bleed (index_prefer_explicit) ---
#
# A placed part writes its material to the SOLID interior, but boundary cells (the surface shell)
# read as Natural(0) — per-leaf material is sampled at leaf centre, so a leaf straddling the
# part/terrain boundary lands on the terrain side. Without the fix, the mesher samples one cell at
# v - n*0.5 and a boundary vertex reads that 0 shell -> natural colour -> the part's faces bleed
# terrain. The fix scans the face-neighbours and prefers an adjacent explicit id, so a vertex with
# a wood cell within one cell reads wood.

const WOOD := 4

# A solid wood box centred in the root, with its material written only to the INTERIOR (one-cell
# shell of 0 at the surface — the per-leaf-boundary effect). Returns {data, indices}.
func _wood_box(half: float, interior_inset: float) -> Dictionary:
    var data := PackedFloat32Array()
    var indices := PackedByteArray()
    data.resize(DIM * DIM * DIM)
    indices.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                var p := Vector3(x, y, z) - CENTER
                var d: float = maxf(maxf(absf(p.x) - half, absf(p.y) - half), absf(p.z) - half)
                data[i] = d
                indices[i] = WOOD if d <= interior_inset else 0   # 0 on the surface shell
                i += 1
    return {"data": data, "indices": indices}

func _mesh_colored(s: Dictionary) -> Array:
    return DCOctreeMesher.new().mesh_clipmap(
        [s.data], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        CENTER, 1e9, DEPTH, Vector3.ZERO, 0.0, 0.0, false, Vector3i.ZERO,
        [s.indices], MaterialPalette.colors())


func test_explicit_material_not_bled_into_natural():
    # Boundary shell indexed 0; every surface vertex still has a wood cell within one cell, so the
    # neighbour-preference must give them all the wood material (a==0) — no natural bleed.
    var arrays := _mesh_colored(_wood_box(8.0, -1.0))
    assert_false(arrays.is_empty(), "meshed the wood box")
    var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
    assert_gt(colors.size(), 100, "got a tessellated, coloured box")
    var natural := 0
    var wood := MaterialPalette.colors()[WOOD]
    for c in colors:
        if c.a >= 0.5:
            natural += 1
        else:
            assert_almost_eq(c.r, wood.r, 0.01, "explicit vertex carries the wood albedo")
    assert_eq(natural, 0, "no wood-box vertex bled to natural")


func test_colored_box_stays_watertight():
    # The colour fix must not perturb geometry — the wood box meshes closed (no holes/cracks).
    var arrays := _mesh_colored(_wood_box(8.0, -1.0))
    var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
    var audit := _edge_audit(idx)
    assert_eq(audit["boundary"], 0, "boundary edges (holes)")
    assert_eq(audit["nonmanifold"], 0, "non-manifold edges")


# The OTHER direction: a Natural surface BESIDE explicit material must NOT bleed to that material
# (the "ground around the log turns to wood" regression). A solid block, natural on the left half,
# wood on the right, flat top — the top surface vertices over the natural half point UP, so their
# inward sample is the natural body below; the wood is a sideways neighbour and must be excluded.
func _split_block() -> Dictionary:
    var data := PackedFloat32Array()
    var indices := PackedByteArray()
    data.resize(DIM * DIM * DIM)
    indices.resize(DIM * DIM * DIM)
    var top := 20.0
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                data[i] = float(y) - top          # solid below y=20, air above; flat top
                indices[i] = WOOD if (float(y) < top and x >= 16) else 0   # right half wood, left natural
                i += 1
    return {"data": data, "indices": indices}

func test_natural_surface_not_bled_to_explicit():
    var arrays := _mesh_colored(_split_block())
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
    var bled := 0
    for j in verts.size():
        # Top-surface vertices clearly on the natural (left) half, incl. one cell from the x=16
        # boundary — these must stay natural; the old omnidirectional scan bled them to wood.
        if verts[j].y > 18.0 and verts[j].x <= 15.0 and colors[j].a < 0.5:
            bled += 1
    assert_eq(bled, 0, "natural surface beside wood stayed natural (no outward bleed)")
