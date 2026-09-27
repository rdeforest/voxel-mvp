extends GutTest

# PartIndex fed by real ConstructionAction placements on the game's EditStore field: a part is
# registered under the cells its imprint made solid (the solid flips of its matter-changed event), so
# carving away what it truly occupies releases it — no AABB-footprint cell the imprint never filled
# keeps it alive. Every writer's carve counts, terraforming included.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

const COLUMN_X := 100.0
const COLUMN_Z := 100.0

const MatterLog := preload("res://test/support/matter_log.gd")

var _log: MatterLog


func before_each() -> void:
    _log = MatterLog.new()

func after_each() -> void:
    _log = null


func _store() -> EditStore:
    var store := EditStore.new()
    store.setup(Vector3(-128.0, -128.0, -128.0), 256.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return store

func _ctx(store: EditStore) -> ActionContext:
    return ActionContext.new(store, null, null)

func _aloft() -> Vector3:
    var surface := EditStore.terrain_surface(COLUMN_X, COLUMN_Z, BASE, AMP, PERIOD, OCTAVES, SEED)
    return Vector3(floorf(COLUMN_X), floorf(surface) + 20.0, floorf(COLUMN_Z))

func _sorted(cells: Array[Vector3i]) -> Array[Vector3i]:
    var out := cells.duplicate()
    out.sort()
    return out


# A beam turned 45 degrees, resting on a pillar: its AABB footprint holds corner cells the imprint
# never fills. Carving out everything around the beam releases the record.
func test_rotated_part_is_released_when_its_imprint_is_carved_away() -> void:
    var store := _store()
    var index := PartIndex.new()
    var pos   := _aloft() + Vector3(0.5, 0.0, 0.5)
    var beam  := preload("res://assets/parts/beam/beam.tres")
    CsgAction.new(CsgBoxShape.new(Vector3(1.6, 2.0, 1.6)), Transform3D(Basis(), pos + Vector3.DOWN),
        CsgState.Op.ADD, &"Stone", _ctx(store)).execute()
    _log.clear()

    var action := ConstructionAction.new(beam, pos, Vector3(0.0, 45.0, 0.0), &"Wood", _ctx(store))
    assert_true(action.validate(), "the beam rests on the pillar")
    action.execute()
    var unfilled := action._part_cells().filter(
        func(c: Vector3i) -> bool: return not TerrainProbe.is_solid(store, c))
    assert_false(unfilled.is_empty(), "the footprint holds cells the imprint never filled (else this tests nothing)")

    assert_eq(index.count(), 1, "the placement is recorded")
    assert_false(_log.solid.is_empty(), "the beam flips cells solid")
    if _log.solid.is_empty():
        return

    var id := index.part_at(_log.solid[0])
    assert_eq(_sorted(index.record(id).cells), _sorted(_log.solid), "under exactly the cells it flipped solid")

    var placed := _log.solid.duplicate()
    var hull   := (action._xform() * action._shape().local_aabb()).grow(1.0)
    CsgAction.new(CsgBoxShape.new(hull.size), Transform3D(Basis(), hull.get_center()),
        CsgState.Op.SUBTRACT, &"Stone", _ctx(store)).execute()
    for cell: Vector3i in placed:
        assert_false(TerrainProbe.is_solid(store, cell), "the carve emptied %s" % cell)
    assert_eq(index.count(), 0, "carving away everything the part occupies releases it")


# A part thinner than a cell that covers no cell centre writes real geometry but makes no cell
# solid; with no cell to carve, a record could never be released, so none is made.
func test_part_that_fills_no_cell_leaves_no_record() -> void:
    var store := _store()
    var index := PartIndex.new()
    var thin  := preload("res://assets/parts/log/log.tres")
    var action := ConstructionAction.new(thin, _aloft() + Vector3(0.0, 0.6, 0.0), Vector3.ZERO,
        &"Wood", _ctx(store))
    assert_true(VoxelImprint.lattice(store, action._shape(), action._xform(), CsgState.Op.ADD).writes,
        "the log writes geometry")
    action.execute()
    assert_true(_log.solid.is_empty(), "the log flips no cell centre (else this tests nothing)")
    assert_eq(index.count(), 0, "a placement that made no cell solid leaves no record")


# A slab resting on the generator's sloped ground, recorded; returns the cells it made solid.
func _grounded_slab(store: EditStore, index: PartIndex) -> Array[Vector3i]:
    var slab   := preload("res://assets/parts/slab/slab.tres")
    var ground := EditStore.terrain_surface(COLUMN_X + 0.5, COLUMN_Z + 0.5, BASE, AMP, PERIOD, OCTAVES, SEED)
    var action := ConstructionAction.new(slab, Vector3(COLUMN_X + 0.5, ground - 0.4, COLUMN_Z + 0.5),
        Vector3.ZERO, &"Wood", _ctx(store))
    assert_true(action.validate(), "the slab rests on the ground")
    action.execute()
    assert_eq(index.count(), 1, "the placement is recorded")
    return _log.solid.duplicate()


# Terraforming carves parts like any other write: a flatten through a slab empties every cell it
# made solid, so the record goes; a lower sinks only the middle, so the record keeps exactly the
# cells the lower left solid.
#
# The flatten runs on a flat platform, so the cut's column test (it only cuts a column with air above the plane
# within its radius) sees the whole slab: a flatten at the platform's top takes all of it.
func test_flatten_through_a_part_releases_its_record() -> void:
    var store := _store()
    var index := PartIndex.new()
    var top   := _aloft() + Vector3(0.5, 0.0, 0.5)
    CsgAction.new(CsgBoxShape.new(Vector3(6.0, 2.0, 6.0)), Transform3D(Basis(), top + Vector3.DOWN),
        CsgState.Op.ADD, &"Stone", _ctx(store)).execute()
    _log.clear()
    var slab := ConstructionAction.new(preload("res://assets/parts/slab/slab.tres"), top, Vector3.ZERO,
        &"Wood", _ctx(store))
    assert_true(slab.validate(), "the slab rests on the platform")
    slab.execute()
    var placed := _log.solid.duplicate()
    assert_eq(index.count(), 1, "the placement is recorded")

    var flatten := FlattenAction.new(top, Vector3.UP, 3.0, _ctx(store))
    assert_true(flatten.validate(), "the flatten writes")
    flatten.execute()
    for cell: Vector3i in placed:
        assert_false(TerrainProbe.is_solid(store, cell), "precondition: the flatten emptied %s" % cell)
    assert_eq(index.count(), 0, "flattening away everything the part occupies releases it")


func test_lower_through_a_part_releases_the_cells_it_empties() -> void:
    var store  := _store()
    var index  := PartIndex.new()
    var placed := _grounded_slab(store, index)
    var id     := index.part_at(placed[0])

    _log.clear()
    var lower := LowerAction.new(Vector3(COLUMN_X + 0.5, float(placed[0].y), COLUMN_Z + 0.5), 3.0, _ctx(store))
    assert_true(lower.validate(), "the lower writes")
    lower.execute()
    var kept := placed.filter(func(c: Vector3i) -> bool: return TerrainProbe.is_solid(store, c))
    assert_true(kept.size() < placed.size(), "precondition: the lower emptied some of the part's cells")
    assert_false(kept.is_empty(), "precondition: and left some (else the flatten test covers it)")
    assert_eq(_sorted(index.record(id).cells), _sorted(kept), "the record keeps exactly the cells still solid")
