extends GutTest

# The world-fixed octree scaffold (doc 16 THE GOAL): DCOctreeMesher.mesh_world builds + meshes ONE
# octree anchored to fixed WORLD coordinates, sampling the EditStore field (generator + edits) DIRECTLY
# per cell — no concentric clipmap, no geomorph. These guard the seam the live render migrates onto:
# the direct-sampled surface must be watertight on the REAL Phase-B terrain field, WITH the screen-error
# collapse on (the test gap that bit the old prune — see dc-sdf-not-unit-distance), and its topology must
# match a baked grid of the same field (direct sampling == sampling a grid of it).

# Generator params mirror EditStoreManager (the live world's field) so we test the real terrain.
const ROOT_ORIGIN := Vector3(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0
const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

const SIZE   := 32     # depth-5 octree, [0,32]^3 lattice
const DIM    := SIZE + 1
const DEPTH  := 5
const WALL_EPS := 2.0   # DC places a vertex INSIDE its cell, so a rim vertex sits up to ~1 unit off the
                        # wall — the boundary band must be ~2 units thick (matches test_dc_real_terrain)


func _store() -> EditStore:
    var s := EditStore.new()
    s.setup(ROOT_ORIGIN, ROOT_SIZE, BASE, AMP, PERIOD, OCTAVES, SEED)
    return s


# Surface y at a world (x,z) — bisect the field's zero crossing (negative = solid, positive = air).
func _surface_y(s: EditStore, x: float, z: float) -> float:
    var lo := -400.0   # deep solid
    var hi := 400.0    # high air
    for _i in 48:
        var mid := (lo + hi) * 0.5
        if s.sample(Vector3(x, mid, z)) < 0.0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) * 0.5


# A vertex on ANY of the 6 outer faces of the region is a legit boundary (the surface exits there);
# a count-1 edge in the interior is a crack. Robust to which walls a heightfield exits.
func _on_boundary(v: Vector3) -> bool:
    return absf(v.x) < WALL_EPS or absf(v.x - SIZE) < WALL_EPS \
        or absf(v.y) < WALL_EPS or absf(v.y - SIZE) < WALL_EPS \
        or absf(v.z) < WALL_EPS or absf(v.z - SIZE) < WALL_EPS

func _crack_audit(verts: PackedVector3Array, idx: PackedInt32Array) -> Dictionary:
    var counts := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
            var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[key] = counts.get(key, 0) + 1
    var interior := 0
    var nonmanifold := 0
    for k in counts:
        if counts[k] > 2:
            nonmanifold += 1
        elif counts[k] == 1 and not (_on_boundary(verts[k.x]) and _on_boundary(verts[k.y])):
            interior += 1
    return {"interior": interior, "nonmanifold": nonmanifold}


# A world-aligned region centred on the surface at world xz (0.5, 0.5), in lattice units (base_cell 1 →
# lattice == world). The cube spans world y [surf-16, surf+16] so the surface sits near the middle.
func _region_origin(s: EditStore) -> Vector3i:
    var surf := _surface_y(s, 0.5, 0.5)
    return Vector3i(-16, int(round(surf)) - 16, -16)


# Mesh the world-fixed region by sampling EditStore DIRECTLY (mesh_world).
func _world_arrays(s: EditStore, origin: Vector3i, collapse: bool) -> Array:
    var cam := Vector3(16, 16, 220) if collapse else Vector3.ZERO   # off the +z side so distant cells collapse
    return DCOctreeMesher.new().mesh_world(s, origin, DEPTH, 1.0, cam, 500.0, 2.0, collapse)

# Mesh the SAME region via the trusted path: bake a fill_region grid of the field, feed mesh_clipmap.
func _baked_arrays(s: EditStore, origin: Vector3i, collapse: bool) -> Array:
    var grid := s.fill_region(origin, DIM, 1.0, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO)
    var cam := Vector3(16, 16, 220) if collapse else Vector3.ZERO
    return DCOctreeMesher.new().mesh_clipmap(
            [grid], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
            Vector3(16, 16, 16), 1e9, DEPTH, cam, 500.0, 2.0, collapse)

func _audit_of(arrays: Array) -> Dictionary:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    return _crack_audit(verts, idx)


# Seam works AND is faithful: a direct-sampled world octree (no collapse) is CRACK-FREE on the real
# terrain field (interior boundary edges == 0 — the real watertightness, holes you'd see through), and
# its full audit EQUALS the trusted baked-grid mesher's on the same field — so direct sampling reproduces
# the mesher we trust exactly. (nonmanifold may be nonzero: this region has zero-area grazing-corner
# degenerate edges — a known deferred artifact, invisible — present identically in BOTH paths, so we
# assert equivalence, not absolute zero.)
func test_mesh_world_watertight():
    var s := _store()
    var origin := _region_origin(s)
    var world := _world_arrays(s, origin, false)
    assert_false(world.is_empty(), "mesh_world produced a surface")
    var verts: PackedVector3Array = world[Mesh.ARRAY_VERTEX]
    assert_gt(verts.size(), 200, "meaningfully tessellated")
    var wa := _audit_of(world)
    var ba := _audit_of(_baked_arrays(s, origin, false))
    assert_eq(wa["interior"], 0, "crack-free (no interior boundary edges / holes)")
    assert_eq(wa["interior"], ba["interior"], "matches the trusted path's cracks (faithful)")
    assert_eq(wa["nonmanifold"], ba["nonmanifold"], "matches the trusted path's non-manifold edges (faithful)")


# WITH the screen-error collapse on: the camera sits off the region so collapse fires. Guard the failure
# the gate exists for — the collapse must produce a real surface with NO degenerate (inf/nan) vertex (the
# bug that sank the old gradient prune). We do NOT crack-audit a cut region here: once cells collapse, a
# boundary cell's vertex sits far inside the wall, so the "near a wall = legit boundary" test mis-flags
# rim edges as cracks (the trusted suite skips the audit under collapse for the same reason). Crack-free
# WITH collapse is the in-game `dcinval` GUI gate (doc 16) — render correctness needs GPU eyes.
func test_mesh_world_collapse_produces_finite_surface():
    var s := _store()
    var origin := _region_origin(s)
    var world := _world_arrays(s, origin, true)
    assert_false(world.is_empty(), "mesh_world (collapse) produced a surface")
    var verts: PackedVector3Array = world[Mesh.ARRAY_VERTEX]
    assert_gt(verts.size(), 100, "collapse kept a surface")
    for v in verts:
        assert_true(is_finite(v.x) and is_finite(v.y) and is_finite(v.z), "no degenerate (inf/nan) vertex")


# Persistence (the incremental-movement foundation): mesh_world RETAINS its octree, so remesh() re-decides
# collapse against a new camera with NO field resampling. A re-walk at the build camera must reproduce the
# build byte-for-byte; a re-walk at a nearer camera must equal a fresh build there (and keep more detail).
func test_mesh_world_remesh_rewalk_equals_fresh_build():
    var s := _store()
    var origin := _region_origin(s)
    var far  := Vector3(16, 16, 220)
    var near := Vector3(16, 16, 80)
    var m := DCOctreeMesher.new()
    var built_far: Array = m.mesh_world(s, origin, DEPTH, 1.0, far, 500.0, 1.0, true)
    var rewalk_far: Array = m.remesh(far, 500.0, 1.0)
    assert_eq(rewalk_far[Mesh.ARRAY_VERTEX], built_far[Mesh.ARRAY_VERTEX], "remesh at the build camera reproduces its vertices")
    assert_eq(rewalk_far[Mesh.ARRAY_INDEX],  built_far[Mesh.ARRAY_INDEX],  "...and its indices")
    var rewalk_near: Array = m.remesh(near, 500.0, 1.0)
    var fresh_near: Array = DCOctreeMesher.new().mesh_world(s, origin, DEPTH, 1.0, near, 500.0, 1.0, true)
    assert_eq(rewalk_near[Mesh.ARRAY_VERTEX], fresh_near[Mesh.ARRAY_VERTEX], "re-walk at a new camera equals a fresh build there (no resample)")
    assert_eq(rewalk_near[Mesh.ARRAY_INDEX],  fresh_near[Mesh.ARRAY_INDEX],  "...indices too")
    assert_gt((rewalk_near[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),
              (rewalk_far[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),
              "the nearer re-walk kept more detail (collapse re-decided on the retained tree, not re-sampled)")


# Direct field sampling == sampling a baked grid of the same field: the crossing topology is decided by
# the field's SIGN at integer cell corners — identical whether read direct (mesh_world) or via a
# fill_region grid (mesh_clipmap) — so the two meshes share a vertex count (positions differ only by the
# analytic-vs-trilinear gradient between corners). Anchors the direct-sampling seam to a trusted path.
func test_mesh_world_matches_baked_grid_topology():
    var s := _store()
    var origin := _region_origin(s)
    var wv: PackedVector3Array = _world_arrays(s, origin, false)[Mesh.ARRAY_VERTEX]
    var bv: PackedVector3Array = _baked_arrays(s, origin, false)[Mesh.ARRAY_VERTEX]
    assert_eq(wv.size(), bv.size(), "direct-sampled vertex count == baked-grid vertex count (same topology)")
