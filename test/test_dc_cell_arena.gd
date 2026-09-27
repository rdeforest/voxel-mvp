extends GutTest

# The octree's cells live in CellArena (engine/voxel_dc/dc_cell_arena.h): fixed-size RAM blocks, a hard
# capacity from the RAM budget (Q4), and no copying on growth. Refinement stops gracefully at the cell
# limit, min(max_cells, capacity), on every path that allocates cells: the level-sync build, a move, a
# drain and an edit. The arena capacity and max_cells share that one limit (Octree::cell_limit), so the
# octree tests drive it through max_cells; building ~65M cells to reach the capacity is not a unit test.
#
# Generator params mirror EditStoreManager (the live world's field), as in test_dc_world_octree. The root
# is 64 so the half-size cells a graft leaves coarse are small enough to mesh, and the surface sits at
# local y 32, inside the coarse cells rather than on their faces.

const ROOT_ORIGIN := Vector3(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0
const BASE        := 30.0
const AMP         := 140.0
const PERIOD      := 1000.0
const OCTAVES     := 2
const SEED        := 1337

const SIZE       := 64
const DEPTH      := 6
const CAM        := Vector3(16, 16, 120)
const PROJ       := 500.0
const COARSE     := 32.0
const FINE       := 8.0
const WIN_FULL   := Vector3i(SIZE, SIZE, SIZE)
const WIN_NEAR   := Vector3i(48, SIZE, SIZE)
const WIN_SLIVER := Vector3i(16, SIZE, SIZE)
const GRAFT_X    := 48.0
const DRAIN_US   := 100
const MAX_DRAINS := 20000
const COVERED    := 0.7   # of the unlimited surface area; measured 0.74-0.86, a hole measures 0
const LIMIT_WARNING := "cell limit"
const CAVITY_R   := 5.0
const CAVITY_AT  := Vector3(32, 6, 32)   # deep in solid ground, where the pruned cells are coarse
const CAVITY_SHOWN := 0.8  # of the unlimited edit's cavity area; measured 1.03, and 0.54 unresampled


func _store() -> EditStore:
    var s := EditStore.new()
    s.setup(ROOT_ORIGIN, ROOT_SIZE, BASE, AMP, PERIOD, OCTAVES, SEED)
    return s


func _surface_y(s: EditStore, x: float, z: float) -> float:
    var lo := -400.0
    var hi := 400.0
    for _i in 48:
        var mid := (lo + hi) * 0.5
        if s.sample(Vector3(x, mid, z)) < 0.0:
            lo = mid
        else:
            hi = mid

    return (lo + hi) * 0.5


func _region_origin(s: EditStore) -> Vector3i:
    return Vector3i(-SIZE / 2, int(round(_surface_y(s, 0.5, 0.5))) - SIZE / 2, -SIZE / 2)


# XZ-projected surface area of the triangles centred at x >= x_min (lattice-local). The terrain here is a
# heightfield, so a covered footprint projects to about its own area and a hole (absent cells) to none.
# Open-edge counts can't tell a hole from coarse-cell undersampling, which leaves open edges of its own.
func _xz_area(arrays: Array, x_min: float) -> float:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var area := 0.0
    for i in range(0, idx.size(), 3):
        var a := verts[idx[i]]
        var b := verts[idx[i + 1]]
        var c := verts[idx[i + 2]]
        if (a.x + b.x + c.x) / 3.0 >= x_min:
            area += absf((b - a).cross(c - a).y) * 0.5

    return area


# Surface area of the triangles centred within r of c (lattice-local): how much of a carved cavity shows.
func _area_near(arrays: Array, c: Vector3, r: float) -> float:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    var area := 0.0
    for i in range(0, idx.size(), 3):
        var a := verts[idx[i]]
        var b := verts[idx[i + 1]]
        var d := verts[idx[i + 2]]
        if ((a + b + d) / 3.0).distance_to(c) <= r:
            area += (b - a).cross(d - a).length() * 0.5

    return area


func _build(s: EditStore, origin: Vector3i, win: Vector3i, eps: float, limit: int) -> DCOctreeMesher:
    var m := DCOctreeMesher.new()
    m.mesh_world(s, origin, DEPTH, 1.0, CAM, PROJ, eps, true, PackedColorArray(), origin, origin + win, limit)
    return m


# The C++ side logs the limit once per process; whichever test hits it first sees that warning.
func _accept_limit_warning() -> void:
    for e in get_errors():
        if e.contains_text(LIMIT_WARNING):
            e.handled = true


func test_arena_growth_across_blocks_keeps_data_and_addresses():
    var block: int = DCOctreeMesher.check_cell_arena(2, 2).block
    var count := block * 3 + 123
    var r := DCOctreeMesher.check_cell_arena(count, count)

    assert_true(r.values_kept, "every value survives growth past several block boundaries")
    assert_true(r.addresses_kept, "growth never moves an element (no realloc copy)")
    assert_eq(r.size, count, "the arena holds exactly what was grown")
    assert_eq(r.room, 0, "grown to capacity: no room left, and no abort getting there")


func test_capacity_fits_int_indices():
    var cap := DCOctreeMesher.get_cell_capacity()

    assert_gt(cap, 0, "the RAM budget holds some cells")
    assert_lt(cap, 1 << 31, "cell indices are int")


func test_unlimited_build_does_not_flag_the_limit():
    var m := _build(_store(), _region_origin(_store()), WIN_FULL, COARSE, 0)

    assert_false(m.get_cell_limit_hit(), "a build well under the capacity is not limited")
    assert_false(m.is_at_cell_limit(), "and has room left")


func test_build_stops_at_the_limit():
    var s := _store()
    var origin := _region_origin(s)
    var free := _build(s, origin, WIN_FULL, COARSE, 0).remesh(CAM, PROJ, COARSE)
    var m := _build(s, origin, WIN_FULL, FINE, 200)
    var arrays := m.remesh(CAM, PROJ, FINE)

    assert_lte(m.get_octree_cell_count(), 200, "the level-sync build stays within the limit")
    assert_true(m.get_cell_limit_hit(), "and reports that it stopped")
    assert_gt(_xz_area(arrays, 0.0), COVERED * _xz_area(free, 0.0), "the coarse tree covers the window")
    _accept_limit_warning()


# A move grafts the far strip of the window, whose coarse absent cells want refining. At the limit they
# can't, so they must become present coarse leaves: left absent, the strip would be a hole.
func _move_at_limit(refine_budget: int) -> void:
    var s := _store()
    var origin := _region_origin(s)
    var free := _build(s, origin, WIN_NEAR, COARSE, 0)
    var limit := free.get_octree_cell_count()
    var want := free.grow_world(CAM, PROJ, COARSE, origin, origin + WIN_FULL)
    var m := _build(s, origin, WIN_NEAR, COARSE, limit)
    var arrays := m.grow_world(CAM, PROJ, COARSE, origin, origin + WIN_FULL, refine_budget)

    assert_lte(m.get_octree_cell_count(), limit, "the move stays within the limit")
    assert_true(m.get_cell_limit_hit(), "and reports that it stopped")
    assert_true(m.is_at_cell_limit(), "with no room left")
    assert_false(m.get_refine_pending(), "nothing is left to drain until slots are freed")
    assert_gt(_xz_area(arrays, GRAFT_X), COVERED * _xz_area(want, GRAFT_X), "the grafted strip is covered, coarse, with no hole")
    _accept_limit_warning()


func test_unbudgeted_move_stops_at_the_limit():
    _move_at_limit(-1)


func test_budgeted_move_stops_at_the_limit():
    _move_at_limit(0)


func test_drain_stops_at_the_limit():
    var s := _store()
    var origin := _region_origin(s)
    var free := _build(s, origin, WIN_FULL, COARSE, 0)
    var limit := free.get_octree_cell_count() + 2000
    var m := _build(s, origin, WIN_FULL, COARSE, limit)
    var arrays := m.grow_world(CAM, PROJ, FINE, origin, origin + WIN_FULL, DRAIN_US, Vector3i(), Vector3i(), false)
    var drains := 0
    while m.get_refine_pending() and drains < MAX_DRAINS:
        arrays = m.grow_world(CAM, PROJ, FINE, origin, origin + WIN_FULL, DRAIN_US, Vector3i(), Vector3i(), true)
        drains += 1

    assert_false(m.get_refine_pending(), "the drain stops instead of spinning at the limit")
    assert_lte(m.get_octree_cell_count(), limit, "refinement stayed within the limit")
    assert_true(m.get_cell_limit_hit(), "and reports that it stopped")
    assert_gt(_xz_area(arrays, 0.0), COVERED * _xz_area(free.remesh(CAM, PROJ, COARSE), 0.0), "the partly refined surface has no holes")
    _accept_limit_warning()


# An edit that adds surface wants to subdivide. At the limit the edited cells stay coarse but must be
# re-sampled, or the edit would not show. A cavity carved in solid ground adds surface without coarsening
# anything, so the edit frees no slots it could refine into.
func test_edit_at_the_limit_resamples_coarse():
    var s := _store()
    var origin := _region_origin(s)
    var free := _build(s, origin, WIN_FULL, FINE, 0)
    var limit := free.get_octree_cell_count()
    var m := _build(s, origin, WIN_FULL, FINE, limit)
    var before := m.remesh(CAM, PROJ, FINE)
    var ctr := Vector3(origin) + CAVITY_AT
    s.stamp_sphere(ctr, CAVITY_R, VoxelConstants.STORE_OP_SUBTRACT, 0, 1.0)
    var dmin := Vector3i((ctr - Vector3.ONE * (CAVITY_R + 1.0)).floor())
    var dmax := Vector3i((ctr + Vector3.ONE * (CAVITY_R + 1.0)).ceil())
    var want := free.edit_world(s, CAM, PROJ, FINE, dmin, dmax)
    var after := m.edit_world(s, CAM, PROJ, FINE, dmin, dmax)

    assert_lte(m.get_octree_cell_count(), limit, "the edit stays within the limit")
    assert_true(m.get_cell_limit_hit(), "and reports that it stopped")
    assert_gt(_area_near(after, CAVITY_AT, CAVITY_R + 2.0), CAVITY_SHOWN * _area_near(want, CAVITY_AT, CAVITY_R + 2.0),
            "the cavity shows in the coarse cells")
    assert_gt(_xz_area(after, 0.0), COVERED * _xz_area(before, 0.0), "without holes")
    _accept_limit_warning()


# dcmaxcells lowered mid-session below the slots in use closes refinement; an eviction reopens it even
# though the slot count never shrinks (freed slots go to the free list). A gate on the slot count latched.
func test_lowered_budget_reopens_after_eviction():
    var s := _store()
    var origin := _region_origin(s)
    var m := _build(s, origin, WIN_FULL, FINE, 0)
    var budget := m.get_octree_cell_count() / 2
    m.set_cell_budget(budget)

    assert_true(m.is_at_cell_limit(), "a budget below the cells in use closes refinement")

    m.grow_world(CAM, PROJ, FINE, origin, origin + WIN_SLIVER)

    assert_gte(m.get_octree_cell_count(), budget, "the slot count still exceeds the budget")
    assert_false(m.is_at_cell_limit(), "the eviction freed room, so refinement reopens")


# The limit counts live cells: evicted slots wait on the free list and are room, not use. So a
# status reporting slots overstates how close the tree is to the limit once anything was evicted.
func test_live_count_is_what_the_limit_counts():
    var s := _store()
    var origin := _region_origin(s)
    var m := _build(s, origin, WIN_FULL, FINE, 0)

    assert_eq(m.get_octree_live_cell_count(), m.get_octree_cell_count(), "a fresh build has no freed slots")

    m.grow_world(CAM, PROJ, FINE, origin, origin + WIN_SLIVER)
    var live := m.get_octree_live_cell_count()

    assert_lt(live, m.get_octree_cell_count(), "the evicted cells stay slots but are not live")

    m.set_cell_budget(live + 8)
    assert_false(m.is_at_cell_limit(), "a budget with room for one subdivision past the live cells is open")

    m.set_cell_budget(live + 7)
    assert_true(m.is_at_cell_limit(), "one cell less and it is closed")
