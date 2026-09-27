extends GutTest

# EditStore.predict_carve: the field that empties exactly a thaw's planned cells and leaves every other
# cell it rewrites on the side it reads now, or a refusal naming the cells that can't all hold.
# On the game's field (EditStoreManager: aligned root, the real generator). Provenance:
# docs/bugs/mpm-thaw-carve-leaves-planned-cells.md, where MpmStructure's corner carve empties 52 of
# a terrain r=3 sphere's 63 planned cells, 143 of r=5's 176, and none of a lone buried cell, and its
# box rewrite flips cells nobody planned.

var _store:   EditStore
var _surface: float


func before_each() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store = manager.store
    _surface = _surface_at(0.0, 0.0)


func _surface_at(x: float, z: float) -> float:
    return EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


# MpmStructure._plan_thaw's plan: the cells in the ball whose centre reads solid.
func _sphere_plan(center: Vector3, radius: float) -> Array[Vector3i]:
    var out: Array[Vector3i] = []
    for cell in VoxelUtils.cells_in_sphere(center, radius):
        if TerrainProbe.is_solid(_store, cell):
            out.append(cell)
    return out


func _sorted(cells: Array[Vector3i]) -> Array[Vector3i]:
    var out := cells.duplicate()
    out.sort()
    return out


# Solve, write, and check the write against the plan: exactly the planned cells went air, nothing
# went solid, and every rewritten cell reads past zero by its margin (the C++ mirrors of
# CELL_EDIT_SDF / CELL_KEEP_SDF are held here to be no weaker than the GDScript constants; equality
# isn't observable from GDScript).
func _assert_carves_exactly(plan: Array[Vector3i]) -> Dictionary:
    return _assert_writes_exactly(plan, _store.predict_carve(plan))


func _assert_writes_exactly(plan: Array[Vector3i], d: Dictionary) -> Dictionary:
    assert_eq(d.conflict, [], "the plan is carveable")
    if not d.has("sdf"):
        return d

    var lat     := SdfLattice.predicted(d)
    var planned := {}
    for cell in plan:
        planned[cell] = true
    var was := {}
    for cell in lat.cells():
        was[cell] = TerrainProbe.is_solid(_store, cell)

    var flips := StoreWrite.write(_store, lat, [] as Array[LatticeEdit])

    assert_eq(_sorted(flips.air), _sorted(plan.filter(func(c: Vector3i) -> bool: return was[c])),
        "exactly the planned solid cells went air")
    assert_eq(flips.solid, [] as Array[Vector3i], "no cell went solid")
    _assert_margins(lat, planned, was)
    return d


func _assert_margins(lat: SdfLattice, planned: Dictionary, was: Dictionary) -> void:
    var short := []
    for cell: Vector3i in was:
        var now := TerrainProbe.sdf(_store, cell)
        var met := now >= VoxelConstants.CELL_EDIT_SDF if planned.has(cell) \
            else (now <= -VoxelConstants.CELL_KEEP_SDF if was[cell] else now >= VoxelConstants.CELL_KEEP_SDF)
        if not met:
            short.append([cell, now])
    assert_eq(short, [], "every rewritten cell reads past zero by its margin")


func test_terrain_sphere_r3_empties_every_planned_cell() -> void:
    var plan := _sphere_plan(Vector3(0.5, _surface - 3.0, 0.5), 3.0)
    assert_eq(plan.size(), 63, "precondition: the bug file's r=3 plan")

    _assert_carves_exactly(plan)


func test_terrain_sphere_r5_empties_every_planned_cell() -> void:
    var plan := _sphere_plan(Vector3(0.5, _surface - 3.0, 0.5), 5.0)
    assert_eq(plan.size(), 176, "precondition: the bug file's r=5 plan")

    _assert_carves_exactly(plan)


func test_lone_buried_cell_empties() -> void:
    var cell := Vector3i(0, int(_surface) - 20, 0)
    assert_true(TerrainProbe.is_solid(_store, cell), "precondition: buried")

    _assert_carves_exactly([cell] as Array[Vector3i])


# A 9^3 block under the ridge: 729 planned cells (the largest the thaw's particle cap allows), some
# of them already air in the generator's field.
func test_buried_block_empties_every_planned_cell() -> void:
    var plan: Array[Vector3i] = []
    for x in 9:
        for y in 9:
            for z in 9:
                plan.append(Vector3i(x - 4, int(_surface) - 16 + y, z - 4))

    _assert_carves_exactly(plan)


# The box rewrite alone, the current field re-encoded at the corners, flips a cell nobody planned at
# many spots (scripts/dev/find_reencode_flip.gd finds them); the solve must keep it on its side.
# Flips to air are common; this one is to air.
func test_near_surface_rewrite_keeps_a_cell_that_would_go_air() -> void:
    _assert_keeps_stray_flips(Vector3(-19.5, _surface_at(-20.0, 14.0), 14.5), "air")


# Flips to solid are rare (none within 20 m of the origin); this spot has one.
func test_near_surface_rewrite_keeps_a_cell_that_would_go_solid() -> void:
    _assert_keeps_stray_flips(Vector3(-79.5, _surface_at(-80.0, -57.0), -56.5), "solid")


func _assert_keeps_stray_flips(center: Vector3, direction: String) -> void:
    var plan := _sphere_plan(center, 1.4)
    var d    := _store.predict_carve(plan)
    assert_true(d.has("sdf"), "the plan is carveable: %s" % [d])
    if not d.has("sdf"):
        return

    var origin := Vector3i(d.origin)
    var plain  := _store.fill_region(origin, d.dim, 1.0, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO)
    var flips  := _store.lattice_flips(plain, d.dim, d.origin, 1.0)
    var stray: Array = flips[direction].filter(func(c: Vector3i) -> bool: return not plan.has(c))
    assert_gt(stray.size(), 0, "precondition: re-encoding the box flips an unplanned cell to " + direction)

    _assert_writes_exactly(plan, d)


# A sharp solid face whose face cells' outer corners are +5: the face cell next to the planned one
# reads solid only while the corners it shares with it stay low. With a 1-cell margin its outer
# corners are the held cube face, so the two cells can't both hold; one more cell of margin frees
# them.
func test_conflict_at_the_held_face_is_proven_then_grown_past() -> void:
    var cell := Vector3i(0, int(_surface) - 20, 0)
    _sharp_face(cell)
    var plan: Array[Vector3i] = [cell]
    var leaves := _store.leaf_count()

    var refused := _store.predict_carve(plan, 1)
    assert_false(refused.has("sdf"), "refused within a 1-cell margin")
    assert_true(refused.proven, "the refusal is a proof, not a sweep budget running out")
    assert_true(refused.pinned, "the proof leans on the held face, so it speaks only for that box")
    assert_eq(_sorted(refused.conflict), _sorted([cell + Vector3i(-1, 0, 0), cell] as Array[Vector3i]),
        "it names the planned cell and the face cell it conflicts with")
    assert_eq(_store.leaf_count(), leaves, "a refusal writes nothing")

    var d := _assert_carves_exactly(plan)
    assert_eq(d.get("margin"), 2, "solved once the box grew a cell")


func _sharp_face(cell: Vector3i, face := 5.0) -> void:
    var dim    := 10
    var origin := Vector3(cell - Vector3i(4, 4, 4))
    var sdf    := PackedFloat32Array()
    sdf.resize(dim * dim * dim)
    for z in dim:
        for y in dim:
            for x in dim:
                sdf[x + dim * (y + dim * z)] = face if int(origin.x) + x < cell.x else -5.5
    _store.write_region(sdf, PackedByteArray(), dim, origin, 1.0)


# The same face, but held at 4.97 rather than 5: the face cell and the planned cell can both hold by
# their margins inside a 1-cell margin, by less than twice those margins. The solver's first aim (2x)
# is then impossible although the problem isn't; it must still solve, not run out its sweep budget.
func test_face_that_fits_only_the_true_margins_is_solved() -> void:
    var cell := Vector3i(0, int(_surface) - 20, 0)
    _sharp_face(cell, 4.97)
    var plan: Array[Vector3i] = [cell]

    var d := _assert_writes_exactly(plan, _store.predict_carve(plan, 1))
    assert_eq(d.get("margin"), 1, "solved within the 1-cell margin")
