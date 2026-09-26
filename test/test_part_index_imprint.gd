extends GutTest

# PartIndex fed by real ConstructionAction placements on the game's EditStore field: a part is
# registered under the cells its imprint made solid (its voxel_added set), so carving away what
# it truly occupies releases it — no AABB-footprint cell the imprint never filled keeps it alive.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

const COLUMN_X := 100.0
const COLUMN_Z := 100.0

var _added: Array[Vector3i] = []


func before_each() -> void:
    _added.clear()
    VoxelEventBusSingleton.subscribe(VoxelAddedEvent.CHANNEL, _on_added)

func after_each() -> void:
    VoxelEventBusSingleton.unsubscribe(VoxelAddedEvent.CHANNEL, _on_added)

func _on_added(e: VoxelAddedEvent) -> void:
    _added.append(e.pos)


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
    _added.clear()

    var action := ConstructionAction.new(beam, pos, Vector3(0.0, 45.0, 0.0), &"Wood", _ctx(store))
    assert_true(action.validate(), "the beam rests on the pillar")
    action.execute()
    var unfilled := action._part_cells().filter(
        func(c: Vector3i) -> bool: return not TerrainProbe.is_solid(store, c))
    assert_false(unfilled.is_empty(), "the footprint holds cells the imprint never filled (else this tests nothing)")

    assert_eq(index.count(), 1, "the placement is recorded")
    assert_false(_added.is_empty(), "the beam flips cells solid")
    if _added.is_empty():
        return

    var id := index.part_at(_added[0])
    assert_eq(_sorted(index.record(id).cells), _sorted(_added), "under exactly its voxel_added cells")

    var hull := (action._xform() * action._shape().local_aabb()).grow(1.0)
    CsgAction.new(CsgBoxShape.new(hull.size), Transform3D(Basis(), hull.get_center()),
        CsgState.Op.SUBTRACT, &"Stone", _ctx(store)).execute()
    for cell: Vector3i in _added:
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
    assert_true(_added.is_empty(), "the log flips no cell centre (else this tests nothing)")
    assert_eq(index.count(), 0, "a placement that made no cell solid leaves no record")
