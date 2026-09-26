extends GutTest

# Gate for the cell -> sample-point convention (a cell is read at its centre,
# VoxelUtils.sample_point). An edit's preview ghost and its voxel_added / voxel_removed events
# must name exactly the cells whose sample-point SDF sign the write actually flipped — not a
# half-cell-shifted guess from testing cell corners against the analytic brush.
#
# Truth is measured independently of the code under test: sample every cell centre in a box
# around the edit before and after execute(), and diff the signs.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

const COLUMN_X := 100.0
const COLUMN_Z := 100.0

var _added:   Array[Vector3i] = []
var _added_material: Dictionary = {}   # cell -> Materials the voxel_added event carried
var _removed: Array[Vector3i] = []


func before_each() -> void:
    _added.clear()
    _added_material.clear()
    _removed.clear()
    VoxelEventBusSingleton.subscribe(VoxelAddedEvent.CHANNEL,   _on_added)
    VoxelEventBusSingleton.subscribe(VoxelRemovedEvent.CHANNEL, _on_removed)

func after_each() -> void:
    VoxelEventBusSingleton.unsubscribe(VoxelAddedEvent.CHANNEL,   _on_added)
    VoxelEventBusSingleton.unsubscribe(VoxelRemovedEvent.CHANNEL, _on_removed)

func _on_added(e: VoxelAddedEvent) -> void:
    _added.append(e.pos)
    _added_material[e.pos] = e.material

func _on_removed(e: VoxelRemovedEvent) -> void:
    _removed.append(e.pos)


func _surface() -> float:
    return EditStore.terrain_surface(COLUMN_X, COLUMN_Z, BASE, AMP, PERIOD, OCTAVES, SEED)

func _store() -> EditStore:
    var store := EditStore.new()
    store.setup(Vector3(-128.0, -128.0, -128.0), 256.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return store

func _ctx(store: EditStore) -> ActionContext:
    return ActionContext.new(store, null, null)


# Cell centre -> SDF over a box of cells generously containing the edit.
func _centres(store: EditStore, around: Vector3, reach: int) -> Dictionary:
    var out := {}
    var c := Vector3i(around.floor())
    for x in range(-reach, reach + 1):
        for y in range(-reach, reach + 1):
            for z in range(-reach, reach + 1):
                var cell := c + Vector3i(x, y, z)
                out[cell] = store.sample(Vector3(cell) + VoxelConstants.VOXEL_CENTER_OFFSET)
    return out

# [became_solid, became_air], each sorted.
func _flipped(before: Dictionary, after: Dictionary) -> Array:
    var solid: Array[Vector3i] = []
    var air:   Array[Vector3i] = []
    for cell: Vector3i in before:
        var was: bool = before[cell] < 0.0
        var now: bool = after[cell]  < 0.0
        if now and not was:
            solid.append(cell)
        elif was and not now:
            air.append(cell)
    solid.sort()
    air.sort()
    return [solid, air]

func _sorted(cells: Array[Vector3i]) -> Array[Vector3i]:
    var out := cells.duplicate()
    out.sort()
    return out


# Run `action` against the independent truth: its preview (taken first) and the events its
# execute() emits must both equal the set of centres whose sign flipped.
func _assert_matches_truth(store: EditStore, action: Action, around: Vector3, reach: int,
        check_events: bool) -> Array:
    var before  := _centres(store, around, reach)
    var preview := action.preview()
    action.execute()
    var truth := _flipped(before, _centres(store, around, reach))
    assert_eq(_sorted(preview.solid), truth[0], "preview.solid == cells whose centre became solid")
    assert_eq(_sorted(preview.air),   truth[1], "preview.air == cells whose centre became air")
    if check_events:
        assert_eq(_sorted(_added),   truth[0], "voxel_added fired for exactly the cells that became solid")
        assert_eq(_sorted(_removed), truth[1], "voxel_removed fired for exactly the cells that became air")
    return truth


# A dig centred off the lattice (straddling cell boundaries on every axis) through the surface,
# so the sphere cuts partial cells on all sides and reaches air above.
func test_dig_events_equal_flipped_sample_points() -> void:
    var store  := _store()
    var center := Vector3(COLUMN_X + 0.37, _surface() - 0.8, COLUMN_Z + 0.71)
    var truth  := _assert_matches_truth(store, DigAction.new(center, 2.6, _ctx(store)), center, 5, true)
    assert_gt(truth[1].size(), 10, "the dig carved a real set of cells")


func test_fill_events_equal_flipped_sample_points() -> void:
    var store  := _store()
    var center := Vector3(COLUMN_X + 0.62, _surface() + 0.9, COLUMN_Z + 0.23)
    var truth  := _assert_matches_truth(
        store, FillAction.new(center, 2.6, _ctx(store), &"Wood"), center, 5, true)
    assert_gt(truth[0].size(), 10, "the fill added a real set of cells")
    _assert_event_materials_match_store(store)


# Raise / Flatten write store lattice points; their ghosts must still name the CELLS that flip.
func test_raise_preview_equals_flipped_sample_points() -> void:
    var store  := _store()
    var center := Vector3(COLUMN_X + 0.4, _surface(), COLUMN_Z + 0.6)
    var truth  := _assert_matches_truth(store, RaiseAction.new(center, 3.0, _ctx(store)), center, 5, false)
    assert_false(truth[0].is_empty(), "the raise lifted some cells to solid")


func test_flatten_preview_equals_flipped_sample_points() -> void:
    var store  := _store()
    var point  := Vector3(COLUMN_X + 0.3, _surface() - 0.6, COLUMN_Z + 0.8)
    var normal := Vector3(0.3, 1.0, 0.1).normalized()
    var truth  := _assert_matches_truth(
        store, FlattenAction.new(point, normal, 3.0, _ctx(store)), point, 5, false)
    assert_false(truth[0].is_empty() and truth[1].is_empty(), "the flatten changed some cells")


# A single-voxel edit flips exactly its own cell, at the cell's sample point.
func test_fill_voxel_flips_exactly_its_cell() -> void:
    var store := _store()
    var cell  := Vector3i(int(COLUMN_X), int(_surface()) + 8, int(COLUMN_Z))
    var truth := _assert_matches_truth(
        store, FillVoxelAction.new(cell, _ctx(store), &"Stone"), Vector3(cell), 3, true)
    assert_eq(truth[0], [cell] as Array[Vector3i], "only the targeted cell became solid")
    assert_eq(store.material_at(Vector3(cell) + VoxelConstants.VOXEL_CENTER_OFFSET), MaterialPalette.index_of(&"Stone"),
        "the cell carries its material at its sample point")


func test_empty_voxel_flips_exactly_its_cell() -> void:
    var store := _store()
    var cell  := Vector3i(int(COLUMN_X), int(_surface()) - 6, int(COLUMN_Z))
    var truth := _assert_matches_truth(store, EmptyVoxelAction.new(cell, _ctx(store)), Vector3(cell), 3, true)
    assert_eq(truth[1], [cell] as Array[Vector3i], "only the targeted cell became air")


# The sphere cell walk: a sample point exactly on the far (+) boundary is included, like the
# near (-) one — the inclusive membership test and the half-open walk agree.
func test_cells_in_sphere_is_symmetric_on_the_boundary() -> void:
    var cells := VoxelUtils.cells_in_sphere(Vector3(0.5, 0.5, 0.5), 2.0)
    assert_true(cells.has(Vector3i( 2, 0, 0)), "+x boundary sample point included")
    assert_true(cells.has(Vector3i(-2, 0, 0)), "-x boundary sample point included")
    assert_true(cells.has(Vector3i( 0, 2, 0)), "+y boundary sample point included")
    assert_true(cells.has(Vector3i( 0, 0, -2)), "-z boundary sample point included")
    assert_false(cells.has(Vector3i( 3, 0, 0)), "past the boundary excluded")


# Every voxel_added event carries the material the store holds for that cell at its sample point.
func _assert_event_materials_match_store(store: EditStore) -> void:
    for cell: Vector3i in _added_material:
        var held := store.material_at(Vector3(cell) + VoxelConstants.VOXEL_CENTER_OFFSET)
        assert_eq(_added_material[cell], Materials.from_name(MaterialPalette.name_of(held)),
            "voxel_added material for %s matches the store (index %d)" % [cell, held])


# The in-game placement: FillVoxel aims at the air cell resting on the surface, EmptyVoxel at the
# top solid cell — where the field is near zero and a neighbour shares 4 / 2 / 1 of the target's
# corners. Over a patch of such cells, every placement flips exactly its own cell (preview and
# events agree), and the isolation is found, not refused.
func test_single_voxel_edits_at_the_surface_flip_exactly_their_cell() -> void:
    var placements := 0
    var refused    := 0
    for x in range(80, 121, 4):
        for z in range(80, 121, 4):
            for solid in [true, false]:
                var store := _store()
                var cell  := _surface_cell(store, x, z, solid)
                var ctx   := _ctx(store)
                var action: Action = FillVoxelAction.new(cell, ctx, &"Wood") if solid \
                    else EmptyVoxelAction.new(cell, ctx)
                placements += 1
                if not action.validate():
                    refused += 1
                    continue
                _added.clear()
                _added_material.clear()
                _removed.clear()
                var truth := _assert_matches_truth(store, action, Vector3(cell), 2, true)
                assert_eq(truth[0] if solid else truth[1], [cell] as Array[Vector3i],
                    "%s at %s flips exactly its cell" % ["fill" if solid else "empty", cell])
                assert_true((truth[1] if solid else truth[0]).is_empty(), "and nothing the other way")
                if solid:
                    _assert_event_materials_match_store(store)
                    assert_eq(store.material_at(Vector3(cell) + VoxelConstants.VOXEL_CENTER_OFFSET),
                        MaterialPalette.index_of(&"Wood"), "the filled cell carries its material")
    assert_lt(refused, placements / 20, "isolating corner writes exist at the surface (%d/%d refused)" % [refused, placements])


# The first air cell above the surface (solid = true: FillVoxel's target), or the top solid cell.
func _surface_cell(store: EditStore, x: int, z: int, air_above: bool) -> Vector3i:
    var solid_at := func(c: Vector3i) -> bool: \
        return store.sample(Vector3(c) + VoxelConstants.VOXEL_CENTER_OFFSET) < 0.0
    var cell := Vector3i(x, int(floor(EditStore.terrain_surface(x + 0.5, z + 0.5,
        BASE, AMP, PERIOD, OCTAVES, SEED))), z)
    while solid_at.call(cell):
        cell.y += 1
    while not solid_at.call(cell + Vector3i.DOWN):
        cell.y -= 1
    return cell if air_above else cell + Vector3i.DOWN


# A 1 m StoreWrite over leaves an earlier edit refined below 1 m must land on those leaves (the
# store samples the finest leaf), and its preview must still equal what flipped.
func test_store_write_lands_on_finer_leaves() -> void:
    var store := _store()
    var cell  := _surface_cell(store, int(COLUMN_X), int(COLUMN_Z), true)
    store.stamp_sphere(Vector3(cell) + Vector3(0.3, -0.6, 0.4), 1.6, VoxelConstants.STORE_OP_UNION,
        MaterialPalette.index_of(&"Stone"), 0.25)
    cell = _surface_cell(store, int(COLUMN_X), int(COLUMN_Z), true)
    var truth := _assert_matches_truth(
        store, FillVoxelAction.new(cell, _ctx(store), &"Wood"), Vector3(cell), 2, true)
    assert_eq(truth[0], [cell] as Array[Vector3i], "the fill landed on the 0.25 m leaves, and only there")

    store = _store()
    var point := Vector3(COLUMN_X + 0.3, _surface() - 0.6, COLUMN_Z + 0.8)
    store.stamp_sphere(point + Vector3(0.5, 0.5, -0.4), 2.2, VoxelConstants.STORE_OP_SUBTRACT, 0, 0.25)
    var flat := _assert_matches_truth(store,
        FlattenAction.new(point, Vector3(0.3, 1.0, 0.1).normalized(), 3.0, _ctx(store)), point, 5, false)
    assert_false(flat[0].is_empty() and flat[1].is_empty(), "the flatten over refined leaves changed cells")


# A CSG brush thinner than a cell writes real geometry even where no cell centre falls inside it;
# it is placed, not refused (refusal means the brush would change nothing).
func test_thin_csg_brush_is_placed() -> void:
    var store := _store()
    var pos   := Vector3(COLUMN_X, _surface() + 30.3, COLUMN_Z)
    var action := CsgAction.new(CsgBoxShape.new(Vector3(0.5, 0.5, 4.0)), Transform3D(Basis(), pos),
        CsgState.Op.ADD, &"Wood", _ctx(store))
    assert_true(action.validate(), "a brush that writes geometry is not refused")
    var preview := action.preview()
    assert_false(preview.refused, "nor shown as refused")
    assert_true(preview.is_empty(), "though it flips no cell centre (else this tests nothing)")
    var was := store.sample(pos)
    action.execute()
    assert_lt(store.sample(pos), was, "the thin brush was written")
