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


# --- One work set per action: preview == events == write (Construction, CSG) ---
#
# Construction and CSG write the VoxelImprint field; their ghost and their voxel events must both
# name the cells that write flips (player safety reads the field itself — tests below). Truth is the measured sign diff.

func _beam() -> Part:
    return preload("res://assets/parts/beam/beam.tres")   # 6x2x2

func _log() -> Part:
    return preload("res://assets/parts/log/log.tres")     # 0.5x0.5x4

# Preview (taken first), events and the measured write must agree. Construction draws its flips
# in the part colour, so its ghost is `part`; everything else draws solid / air.
func _assert_imprint_sets_agree(store: EditStore, action: Action, around: Vector3, reach: int) -> Array:
    var before  := _centres(store, around, reach)
    var preview := action.preview()
    action.execute()
    var truth := _flipped(before, _centres(store, around, reach))
    var ghost_solid := preview.part if action is ConstructionAction else preview.solid
    if action is ConstructionAction:
        assert_true(preview.solid.is_empty(), "construction's ghost is all in the part list")
    assert_eq(_sorted(ghost_solid), truth[0], "ghost == cells the write made solid")
    assert_eq(_sorted(preview.air), truth[1], "ghost air == cells the write emptied")
    assert_eq(_sorted(_added),      truth[0], "voxel_added == cells the write made solid")
    assert_eq(_sorted(_removed),    truth[1], "voxel_removed == cells the write emptied")
    return truth


# A rotated beam sunk into the surface off the lattice: its coarse footprint covers cells that
# were already solid and cells its sub-cell faces never reach — the ghost must not be that.
func test_construction_ghost_events_and_write_agree() -> void:
    var store := _store()
    var pos   := Vector3(COLUMN_X + 0.37, _surface() - 0.4, COLUMN_Z + 0.61)
    var action := ConstructionAction.new(_beam(), pos, Vector3(0.0, 27.0, 8.0), &"Wood", _ctx(store))
    assert_true(action.validate(), "the sunk beam attaches")
    var truth := _assert_imprint_sets_agree(store, action, pos, 6)
    assert_gt(truth[0].size(), 10, "the beam added a real set of cells")
    _assert_event_materials_match_store(store)


func test_csg_add_ghost_events_and_write_agree() -> void:
    var store := _store()
    var pos   := Vector3(COLUMN_X + 0.29, _surface() + 0.35, COLUMN_Z + 0.74)
    var basis := Basis(Vector3(0.3, 1.0, 0.2).normalized(), deg_to_rad(33.0))
    var truth := _assert_imprint_sets_agree(store, CsgAction.new(CsgBoxShape.new(Vector3(3.3, 2.6, 2.2)),
        Transform3D(basis, pos), CsgState.Op.ADD, &"Wood", _ctx(store)), pos, 6)
    assert_gt(truth[0].size(), 10, "the stamp added a real set of cells")
    _assert_event_materials_match_store(store)


func test_csg_subtract_ghost_events_and_write_agree() -> void:
    var store := _store()
    var pos   := Vector3(COLUMN_X + 0.63, _surface() - 0.2, COLUMN_Z + 0.18)
    var basis := Basis(Vector3(1.0, 0.2, 0.4).normalized(), deg_to_rad(21.0))
    var truth := _assert_imprint_sets_agree(store, CsgAction.new(CsgBoxShape.new(Vector3(3.4, 3.1, 3.2)),
        Transform3D(basis, pos), CsgState.Op.SUBTRACT, &"Wood", _ctx(store)), pos, 6)
    assert_gt(truth[1].size(), 10, "the stamp carved a real set of cells")


# The danger check reads the field the imprint writes: a beam resting on a support and crossing
# the player's head (not their body origin) fills a cell inside the capsule, so it is refused and
# its ghost shows refused.
func test_construction_refuses_a_part_through_the_players_head() -> void:
    var store := _store()
    var s     := floorf(_surface()) + 20.0
    var eye   := Vector3(floorf(COLUMN_X) + 0.5, s + 0.5, floorf(COLUMN_Z) + 0.5)   # body origin
    # A support block beside the player whose top the beam rests on.
    CsgAction.new(CsgBoxShape.new(Vector3(2.0, 2.0, 2.0)), Transform3D(Basis(), eye + Vector3(3.0, -0.2, 0.0)),
        CsgState.Op.ADD, &"Stone", _ctx(store)).execute()
    var player := CharacterBody3D.new()
    add_child_autofree(player)
    player.global_position = eye
    var pos    := Vector3(eye.x + 1.5, s + 1.3, eye.z)   # bottom 0.8 m above the body origin
    var action := ConstructionAction.new(_beam(), pos, Vector3.ZERO, &"Wood",
        ActionContext.new(store, player, null))
    var head := Vector3i(eye.floor()) + Vector3i.UP
    assert_true(action.preview().part.has(head), "the beam would fill the cell at the player's head")
    assert_false(action.validate(), "so placing it is refused")
    assert_true(action.preview().refused, "and the ghost shows it refused")
    player.global_position = eye + Vector3(-6.0, 0.0, 0.0)
    assert_true(ConstructionAction.new(_beam(), pos, Vector3.ZERO, &"Wood",
        ActionContext.new(store, player, null)).validate(), "the same beam attaches with the player clear")


# The same refusal for a part THINNER than a cell: the 0.5 x 0.5 x 4 log, laid across the player's
# head (and chest) on the lattice plane, writes real solid inside the capsule while flipping no
# cell centre. The guard reads the field the imprint writes, so it still refuses — and the ghost
# still shows where the refused log would go.
func test_construction_refuses_a_sub_cell_log_through_the_player() -> void:
    for lift: float in [1.0, 0.0]:   # centre plane at head height, then chest height
        var store := _store()
        var s     := floorf(_surface()) + 20.0
        var eye   := Vector3(floorf(COLUMN_X) + 0.5, s + 0.5, floorf(COLUMN_Z) + 0.5)   # body origin
        var bottom := s + lift - 0.25   # the log's centre plane on lattice y = s + lift
        # A support block beside the player whose top the log rests on.
        CsgAction.new(CsgBoxShape.new(Vector3(2.0, 2.0, 2.0)),
            Transform3D(Basis(), Vector3(eye.x + 3.0, bottom - 1.0, eye.z)),
            CsgState.Op.ADD, &"Stone", _ctx(store)).execute()
        var player := CharacterBody3D.new()
        add_child_autofree(player)
        player.global_position = eye
        var pos    := Vector3(eye.x + 1.5, bottom, eye.z + 0.5)   # along x, on lattice z
        var rot    := Vector3(0.0, 90.0, 0.0)
        var action := ConstructionAction.new(_log(), pos, rot, &"Wood", ActionContext.new(store, player, null))
        assert_true(VoxelImprint.lattice(store, action._shape(), action._xform(), CsgState.Op.ADD)
            .flips(store).is_empty(), "the log flips no cell centre (else this tests nothing)")
        assert_false(action.validate(), "a sub-cell log through the player (lift %s) is refused" % lift)
        var preview := action.preview()
        assert_true(preview.refused, "and the ghost shows it refused")
        assert_false(preview.part.is_empty(), "and the ghost still shows where it would go")
        player.global_position = eye + Vector3(-6.0, 0.0, 0.0)
        assert_true(ConstructionAction.new(_log(), pos, rot, &"Wood",
            ActionContext.new(store, player, null)).validate(), "the same log attaches with the player clear")


# CSG is the same imprint: a thin plank through the player's head is refused.
func test_thin_csg_plank_through_the_players_head_is_refused() -> void:
    var store := _store()
    var s     := floorf(_surface()) + 20.0
    var eye   := Vector3(floorf(COLUMN_X) + 0.5, s + 0.5, floorf(COLUMN_Z) + 0.5)
    var player := CharacterBody3D.new()
    add_child_autofree(player)
    player.global_position = eye
    var xform  := Transform3D(Basis(), Vector3(eye.x + 1.5, s + 1.0, eye.z + 0.5))
    var shape  := CsgBoxShape.new(Vector3(4.0, 0.5, 0.5))
    assert_true(VoxelImprint.lattice(store, shape, xform, CsgState.Op.ADD).flips(store).is_empty(),
        "the plank flips no cell centre (else this tests nothing)")
    var action := CsgAction.new(shape, xform, CsgState.Op.ADD, &"Wood", ActionContext.new(store, player, null))
    assert_false(action.validate(), "a thin plank through the player's head is refused")
    assert_true(action.preview().refused, "and shown refused")


# The drop side: a thin void carved in the ground under the player's feet (between cell-centre
# planes, so no centre flips) still empties the support box, and is refused.
func test_thin_carve_under_the_players_feet_is_refused() -> void:
    var store := _store()
    var layer := floorf(_surface()) + 20.0     # the lattice plane the void is carved on
    var top   := layer + 1.3                    # a floor whose top is 1.3 m above it
    CsgAction.new(CsgBoxShape.new(Vector3(8.0, 4.0, 8.0)),
        Transform3D(Basis(), Vector3(floorf(COLUMN_X), top - 2.0, floorf(COLUMN_Z))),
        CsgState.Op.ADD, &"Stone", _ctx(store)).execute()
    var player := CharacterBody3D.new()
    add_child_autofree(player)
    player.global_position = Vector3(floorf(COLUMN_X), top + 1.5, floorf(COLUMN_Z))   # standing on it
    var xform := Transform3D(Basis(), Vector3(floorf(COLUMN_X), layer, floorf(COLUMN_Z)))
    var shape := CsgBoxShape.new(Vector3(3.0, 0.2, 3.0))
    var lat   := VoxelImprint.lattice(store, shape, xform, CsgState.Op.SUBTRACT)
    assert_true(lat.flips(store).is_empty(), "the carve flips no cell centre (else this tests nothing)")
    assert_true(lat.writes, "yet it writes a void")
    var action := CsgAction.new(shape, xform, CsgState.Op.SUBTRACT, &"Wood", ActionContext.new(store, player, null))
    assert_false(action.validate(), "carving the ground under the player's feet is refused")
    player.global_position += Vector3(0.0, 0.0, 12.0)
    assert_true(CsgAction.new(shape, xform, CsgState.Op.SUBTRACT, &"Wood",
        ActionContext.new(store, player, null)).validate(), "the same carve is fine with the player elsewhere")


# Attachment is judged against the part's real (rotated) geometry, not its AABB footprint: a beam
# turned 45 degrees, floating, with a pillar under a footprint corner its box never reaches, is
# refused; the same pillar under the beam itself holds it.
func test_rotated_part_does_not_attach_by_a_footprint_corner() -> void:
    var store := _store()
    var pos   := Vector3(floorf(COLUMN_X) + 0.5, floorf(_surface()) + 20.0, floorf(COLUMN_Z) + 0.5)
    var rot   := Vector3(0.0, 45.0, 0.0)
    var pillar := CsgBoxShape.new(Vector3(1.6, 2.0, 1.6))
    var action := ConstructionAction.new(_beam(), pos, rot, &"Wood", _ctx(store))
    # Of the two footprint-diagonal corners, the one the beam's long axis points away from.
    var inverse := action._xform().affine_inverse()
    var corner := Vector3(pos.x + 2.3, pos.y - 1.0, pos.z - 2.3)
    var other  := Vector3(pos.x + 2.3, pos.y - 1.0, pos.z + 2.3)
    if action._shape().sdf(inverse * other) > action._shape().sdf(inverse * corner):
        corner = other
    CsgAction.new(pillar, Transform3D(Basis(), corner), CsgState.Op.ADD, &"Stone", _ctx(store)).execute()
    action = ConstructionAction.new(_beam(), pos, rot, &"Wood", _ctx(store))
    var footprint_touches := false
    for cell in action._part_cells():
        footprint_touches = footprint_touches or TerrainProbe.is_solid(store, cell) \
            or TerrainProbe.is_solid(store, cell + Vector3i.DOWN)
    assert_true(footprint_touches, "the footprint rule would attach it (else this tests nothing)")
    assert_false(action.validate(), "a floating beam is not attached by a footprint corner")

    store = _store()
    CsgAction.new(pillar, Transform3D(Basis(), Vector3(pos.x, pos.y - 1.0, pos.z)),
        CsgState.Op.ADD, &"Stone", _ctx(store)).execute()
    assert_true(ConstructionAction.new(_beam(), pos, rot, &"Wood", _ctx(store)).validate(),
        "the same beam resting on the pillar attaches")


# A grazing edit — a brush that moves every stored value by less than is_equal_approx's
# tolerance — still changes the field; it is neither refused nor dropped from the write. (The old
# VoxelImprint.compute skipped every such point and CsgAction refused the empty result.) Points
# on the lattice's max faces are left out of the "grazing" check: store.sample reads them from the
# unwritten neighbour leaf, so they don't show what the first stamp wrote.
func test_grazing_csg_edit_is_written() -> void:
    var store := _store()
    var pos   := Vector3(COLUMN_X + 0.3, _surface() - 0.6, COLUMN_Z + 0.2)
    var shape := CsgBoxShape.new(Vector3(2.0, 2.0, 2.0))
    CsgAction.new(shape, Transform3D(Basis(), pos), CsgState.Op.ADD, &"Wood", _ctx(store)).execute()
    var graze := Transform3D(Basis(), pos - Vector3(4e-6, 0.0, 0.0))
    var lat   := VoxelImprint.lattice(store, shape, graze, CsgState.Op.ADD)
    var moved := Vector3i(-1, -1, -1)
    for z in lat.dim - 1:
        for y in lat.dim - 1:
            for x in lat.dim - 1:
                var at  := Vector3i(x, y, z)
                var now := lat.sdf[lat.index(at)]
                var was := store.sample(lat.point(at))
                assert_true(is_equal_approx(now, was), "graze moves %s by < tolerance" % lat.point(at))
                if now != was and moved.x < 0:
                    moved = at
    assert_true(moved.x >= 0, "yet the brush does change a stored value (else this tests nothing)")
    var action := CsgAction.new(shape, graze, CsgState.Op.ADD, &"Wood", _ctx(store))
    assert_true(action.validate(), "the grazing edit is not refused")
    action.execute()
    assert_eq(store.sample(lat.point(moved)), lat.sdf[lat.index(moved)], "and the write lands it")
