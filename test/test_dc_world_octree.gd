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


# Stage B0 + P1 — the resident WINDOW and the surface-sparse prune. A windowed build (a) only builds cells
# overlapping the window (rest ABSENT), and (b) prunes provably surface-free cells via the accel grid. A
# window covering the WHOLE root must STILL reproduce the no-window dense build BYTE-FOR-BYTE — the prune
# only removes empty (non-emitting) cells, so surface cells emit in the same order (surface/order-preserving)
# — while building strictly FEWER cells (proof the prune actually fired, not silently disabled).
func test_mesh_world_full_window_equals_no_window():
    var s := _store()
    var origin := _region_origin(s)
    var cam := Vector3(16, 16, 220)
    var dm := DCOctreeMesher.new()
    var full: Array = dm.mesh_world(s, origin, DEPTH, 1.0, cam, 500.0, 2.0, true)  # no window → dense, no prune
    # win covering [origin, origin + SIZE) — every cell overlaps (nothing absent), prune ON.
    var whole := origin + Vector3i(SIZE, SIZE, SIZE)
    var wm := DCOctreeMesher.new()
    var win: Array = wm.mesh_world(s, origin, DEPTH, 1.0, cam, 500.0, 2.0, true, PackedColorArray(), origin, whole)
    assert_eq(win[Mesh.ARRAY_VERTEX], full[Mesh.ARRAY_VERTEX], "whole-root windowed+pruned == dense vertices (prune is surface/order-preserving)")
    assert_eq(win[Mesh.ARRAY_INDEX],  full[Mesh.ARRAY_INDEX],  "...and indices")
    assert_lt(wm.get_octree_cell_count(), dm.get_octree_cell_count(), "the prune actually fired (fewer cells than the dense build)")


# A window strictly smaller than the surface extent must build LESS: a real (non-empty) surface, but fewer
# vertices than the full build, because the out-of-window cells are absent and contribute no geometry.
func test_mesh_world_subwindow_builds_less():
    var s := _store()
    var origin := _region_origin(s)
    var full_v: PackedVector3Array = _world_arrays(s, origin, false)[Mesh.ARRAY_VERTEX]
    # central column (x,z in [8,24), full height) — contains the surface near xz centre, excludes the edges.
    var wmin := origin + Vector3i(8, 0, 8)
    var wmax := origin + Vector3i(24, SIZE, 24)
    var win: Array = DCOctreeMesher.new().mesh_world(
            s, origin, DEPTH, 1.0, Vector3.ZERO, 0.0, 0.0, false, PackedColorArray(), wmin, wmax)
    var wv: PackedVector3Array = win[Mesh.ARRAY_VERTEX]
    assert_gt(wv.size(), 0, "sub-window still meshed the surface inside it")
    assert_lt(wv.size(), full_v.size(), "sub-window built less than the full root (out-of-window cells absent)")


# Stage B1 — incremental window growth (THE gate): grow_world re-windows the RETAINED octree from window
# A to window B — grafting the cells that entered (sampling ONLY them) and evicting the cells that left —
# and its mesh must be IDENTICAL to a from-scratch mesh_world of window B, while resampling only the
# leading-edge band (not the whole window). This is the incremental-correctness gate the brief demands:
# an incremental build must equal a from-scratch build.
#
# "Identical" = the same SURFACE, not the same array order. The incremental tree appends grown cells and
# leaks evicted ones, so its cell array is laid out differently → place_vertex emits vertices in a
# different order. That's an implementation artifact; what must match is the set of triangles (each as its
# 3 world positions, same winding). Vertex positions ARE bit-identical for corresponding cells (same QEF
# math), so a string signature compares exactly.
const WIN_FULL := Vector3i(SIZE, SIZE, SIZE)

func _vlt(p: Vector3, q: Vector3) -> bool:
    if p.x != q.x: return p.x < q.x
    if p.y != q.y: return p.y < q.y
    return p.z < q.z

func _vstr(p: Vector3) -> String:
    return "%.9f,%.9f,%.9f" % [p.x, p.y, p.z]

# Sorted triangle signatures: each triangle canonicalised by rotating to its lexicographically smallest
# vertex (preserves winding), formatted to full precision, then the whole list sorted. Two meshes with the
# same surface produce equal signature lists regardless of vertex/triangle ordering.
func _tri_sigs(arrays: Array) -> PackedStringArray:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var sigs := PackedStringArray()
    for i in range(0, idx.size(), 3):
        var t := [verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]]]
        var mi := 0
        for k in range(1, 3):
            if _vlt(t[k], t[mi]):
                mi = k
        sigs.append("%s|%s|%s" % [_vstr(t[mi]), _vstr(t[(mi + 1) % 3]), _vstr(t[(mi + 2) % 3])])
    sigs.sort()
    return sigs

func test_grow_world_equals_fresh_build():
    var s := _store()
    var origin := _region_origin(s)
    var cam := Vector3(16, 16, 120)
    # A = left ¾ of the root (x ∈ [0,24)); B = right ¾ (x ∈ [8,32)). Overlap x∈[8,24); B gains x[24,32),
    # loses x[0,8). Full extent in y,z. The surface spans x, so both windows carry real surface.
    var a_min := origin;                       var a_max := origin + Vector3i(24, SIZE, SIZE)
    var b_min := origin + Vector3i(8, 0, 0);   var b_max := origin + WIN_FULL
    var m := DCOctreeMesher.new()
    m.mesh_world(s, origin, DEPTH, 1.0, cam, 500.0, 2.0, true, PackedColorArray(), a_min, a_max)
    var grown: Array = m.grow_world(cam, 500.0, 2.0, b_min, b_max)
    var grow_samples: int = m.get_last_build_sample_count()

    var fm := DCOctreeMesher.new()
    var fresh: Array = fm.mesh_world(s, origin, DEPTH, 1.0, cam, 500.0, 2.0, true, PackedColorArray(), b_min, b_max)
    var fresh_samples: int = fm.get_last_build_sample_count()

    var gv: PackedVector3Array = grown[Mesh.ARRAY_VERTEX]
    var fv: PackedVector3Array = fresh[Mesh.ARRAY_VERTEX]
    assert_eq(gv.size(), fv.size(), "grow A→B has the same vertex count as a fresh build of B (no garbage)")
    assert_eq(_tri_sigs(grown), _tri_sigs(fresh), "grow A→B == fresh build of B (same surface, same winding)")
    assert_gt(grow_samples, 0, "grow sampled the new leading-edge band")
    assert_lt(grow_samples, fresh_samples, "grow resampled ONLY the leading edge, not the whole window (the B1 win)")


# Round trip: A → B → A must return to the original A mesh, byte-for-byte — eviction then re-growth is
# lossless (the retained cells that survived A→B are reused; the ones evicted are rebuilt identically).
func test_grow_world_round_trip_is_lossless():
    var s := _store()
    var origin := _region_origin(s)
    var cam := Vector3(16, 16, 120)
    var a_min := origin;                       var a_max := origin + Vector3i(24, SIZE, SIZE)
    var b_min := origin + Vector3i(8, 0, 0);   var b_max := origin + WIN_FULL
    var m := DCOctreeMesher.new()
    var built_a: Array = m.mesh_world(s, origin, DEPTH, 1.0, cam, 500.0, 2.0, true, PackedColorArray(), a_min, a_max)
    m.grow_world(cam, 500.0, 2.0, b_min, b_max)
    var back_a: Array = m.grow_world(cam, 500.0, 2.0, a_min, a_max)
    var bv: PackedVector3Array = back_a[Mesh.ARRAY_VERTEX]
    var av: PackedVector3Array = built_a[Mesh.ARRAY_VERTEX]
    assert_eq(bv.size(), av.size(), "A→B→A has the same vertex count as the original A build")
    assert_eq(_tri_sigs(back_a), _tri_sigs(built_a), "A→B→A returns to the A surface (evict+regrow is lossless)")


# Stage B1b — bounded resident set (leak-proof, prune-robust): sweep the window forward across the root and
# back to the START (a round trip), repeatedly. The free-list reuses evicted slots, so returning to the same
# window state must give the EXACT same cell-array size every loop — a leak would grow it each loop. (This
# replaces a "< 2× fresh" bound that the P1 prune made too tight: pruning shrinks a static window's cell
# count, but the working set while sweeping varied terrain legitimately exceeds 2× the final window.)
func test_grow_world_bounds_resident_set():
    var s := _store()
    var origin := _region_origin(s)
    var cam := Vector3(16, 16, 120)
    var w := 10 # window width in x; swept across the 32-wide root
    var m := DCOctreeMesher.new()
    var start_min := origin
    var start_max := origin + Vector3i(w, SIZE, SIZE)
    var start_built: Array = m.mesh_world(s, origin, DEPTH, 1.0, cam, 500.0, 2.0, true, PackedColorArray(), start_min, start_max)
    var maxstep := SIZE - w
    var counts: Array[int] = []
    var back_to_start: Array = []
    for _loop in 3:
        for step in range(1, maxstep + 1):                      # sweep forward to the far end
            m.grow_world(cam, 500.0, 2.0, origin + Vector3i(step, 0, 0), origin + Vector3i(step + w, SIZE, SIZE))
        for step in range(maxstep - 1, -1, -1):                 # sweep back to the start window
            back_to_start = m.grow_world(cam, 500.0, 2.0, origin + Vector3i(step, 0, 0), origin + Vector3i(step + w, SIZE, SIZE))
        counts.append(m.get_octree_cell_count())
    assert_eq(counts[2], counts[0], "cell array is identical after each round trip — free-list fully reuses, no leak (%s)" % str(counts))
    # And the round trip is lossless: back at the start window, the surface matches the original build.
    assert_eq(_tri_sigs(back_to_start), _tri_sigs(start_built), "a full sweep returns to the start surface (no corruption)")


# Stage P2.5 — incremental band-diff on a CAMERA MOVE (graded floor re-grade). With a graded floor
# (floor = eps_px·dist/proj), moving the camera changes which cells should be fine: cells it approached must
# refine, cells it receded from must coarsen. grow_world must do this incrementally and produce the SAME
# surface as a fresh build at the new camera — touching only the changed band, not the whole window. (Same
# window both times, so this isolates the floor re-grade from window shift.)
func test_grow_world_regrades_floor_on_camera_move():
    var s := _store()
    # depth-7 root (128 lattice), half = 64 — big enough that the floor grades across the window
    var surf := _surface_y(s, 0.5, 0.5)
    var origin := Vector3i(-64, int(round(surf)) - 64, -64)
    var c := origin + Vector3i(64, 64, 64) # window centre (WORLD lattice)
    var win := Vector3i(48, 48, 48)
    var wmin := c - win
    var wmax := c + win
    var proj := 64.0
    var eps := 8.0 # floor_k = eps/proj = 1/8 → floor grades 1→~11 across the window
    # cameras in the octree LATTICE frame (world − origin; base_cell 1). A small move re-grades a band.
    var cam_a := Vector3(c - origin) + Vector3(0, 24, 0)
    var cam_b := Vector3(c - origin) + Vector3(12, 24, 0)
    var m := DCOctreeMesher.new()
    m.mesh_world(s, origin, 7, 1.0, cam_a, proj, eps, true, PackedColorArray(), wmin, wmax)
    var grown: Array = m.grow_world(cam_b, proj, eps, wmin, wmax)
    var grow_samples: int = m.get_last_build_sample_count()

    var fm := DCOctreeMesher.new()
    var fresh: Array = fm.mesh_world(s, origin, 7, 1.0, cam_b, proj, eps, true, PackedColorArray(), wmin, wmax)
    var fresh_samples: int = fm.get_last_build_sample_count()

    assert_gt((fresh[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 100, "graded build has a real surface")
    assert_eq(_tri_sigs(grown), _tri_sigs(fresh), "grow with camera move == fresh build at the new camera (floor re-graded)")
    assert_gt(grow_samples, 0, "the move re-sampled the changed band")
    assert_lt(grow_samples, fresh_samples, "the move re-sampled only the changed band, not the whole window")


# Incremental accel reuse (perf): grow_world re-bakes the prune accel ONLY when the resident window moves.
# A same-window refine (the budget controller lowering eps with the view held) reuses the last bake — the
# held view keeps refining with no fixed per-grow bake cost — while a window move re-bakes to cover the new
# leading edge. Reuse CORRECTNESS is gated above (regrade grows same-window; equals_fresh grows moved-window).
func test_grow_reuses_accel_when_window_unchanged() -> void:
    var s := _store()
    var origin := _region_origin(s)
    var cam := Vector3(16, 16, 120)
    var a_min := origin;                       var a_max := origin + Vector3i(24, SIZE, SIZE)
    var b_min := origin + Vector3i(8, 0, 0);   var b_max := origin + WIN_FULL
    var m := DCOctreeMesher.new()
    m.mesh_world(s, origin, DEPTH, 1.0, cam, 500.0, 2.0, true, PackedColorArray(), a_min, a_max)
    assert_eq(m.get_accel_bake_count(), 1, "the first build bakes the accel once")
    m.grow_world(Vector3(16, 16, 100), 500.0, 1.0, a_min, a_max)   # same window, lower eps + moved camera → reuse
    assert_eq(m.get_accel_bake_count(), 1, "a same-window refine reuses the accel (no re-bake)")
    m.grow_world(cam, 500.0, 2.0, b_min, b_max)                    # window moves A→B → re-bake the leading edge
    assert_eq(m.get_accel_bake_count(), 2, "a window move re-bakes the accel")


# Parallel accel bake produces byte-identical output to the serial bake: the z-split assigns disjoint
# ranges to each thread, so the samples written are the same values in the same slots as the serial loop.
# Build the same windowed mesh_world twice — once at thread_count=1 (serial), once at thread_count=8
# (parallel) — and assert the triangle sets are identical.
func test_parallel_bake_matches_serial():
    var s := _store()
    var origin := _region_origin(s)
    var cam := Vector3(16, 16, 220)
    var whole := origin + WIN_FULL
    var m1 := DCOctreeMesher.new()
    m1.set_thread_count(1)
    var serial: Array = m1.mesh_world(s, origin, DEPTH, 1.0, cam, 500.0, 2.0, true, PackedColorArray(), origin, whole)
    var m8 := DCOctreeMesher.new()
    m8.set_thread_count(8)
    var parallel: Array = m8.mesh_world(s, origin, DEPTH, 1.0, cam, 500.0, 2.0, true, PackedColorArray(), origin, whole)
    assert_false(serial.is_empty(),   "serial build produced a surface")
    assert_false(parallel.is_empty(), "parallel build produced a surface")
    assert_eq(_tri_sigs(parallel), _tri_sigs(serial), "parallel bake (8 threads) == serial bake (byte-identical surface)")


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
