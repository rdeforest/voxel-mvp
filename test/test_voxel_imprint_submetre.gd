extends GutTest

# VoxelImprint writes part/CSG geometry at the sub-metre leaf (RENDER_BASE_CELL), so a sub-metre
# part is sub-metre solid instead of vanishing/bloating to 1m. A 0.5m-thick log resolves: solid
# through its core, air just past its 0.25m half-thickness — impossible at the old 1m write.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

func _store() -> EditStore:
    var es := EditStore.new()
    es.setup(Vector3(-256, -256, -256), 512.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return es


func test_submetre_log_imprints_at_its_true_thickness() -> void:
    var es := _store()
    var s0 := SparseVoxelOctree.terrain_surface(0, 0, BASE, AMP, PERIOD, OCTAVES, SEED)
    var pos := Vector3(0, s0 + 30.0, 0)         # in open air
    var shape := CsgBoxShape.new(Vector3(0.5, 0.5, 4.0))   # a 0.5m-thick, 4m-long log
    var xform := Transform3D(Basis(), pos)
    var box := VoxelImprint.world_box(shape, xform)
    # apply with empty 1m work → just the fine geometry write (no structural events to a bus here).
    VoxelImprint.apply(es, [], &"Wood", box, shape, xform, CsgState.Op.ADD)

    assert_lt(es.sample(pos), 0.0, "log core is solid")
    assert_lt(es.sample(pos + Vector3(0.1, 0, 0)), 0.0, "within the 0.25m half-thickness is solid")
    assert_gt(es.sample(pos + Vector3(0.6, 0, 0)), 0.0, "0.6m to the side is air — the 0.5m log resolved sub-metre")
    assert_lt(es.sample(pos + Vector3(0, 0, 1.5)), 0.0, "still solid 1.5m along the 4m length")
    assert_eq(es.material_at(pos), MaterialPalette.index_of(&"Wood"), "the log is Wood material")
