extends GutTest

# Parts-as-voxels (stage 2): ConstructionAction imprints the part's box brush into the
# EditStore (SDF + the part's material) instead of spawning a Node3D. Pins the imprint and
# the attach/refuse logic headlessly; the render is GUI-verified.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

const COLUMN_X := 100.0
const COLUMN_Z := 100.0


func _surface() -> float:
    return EditStore.terrain_surface(COLUMN_X, COLUMN_Z, BASE, AMP, PERIOD, OCTAVES, SEED)

func _store() -> EditStore:
    var store := EditStore.new()
    store.setup(Vector3(-128.0, -128.0, -128.0), 256.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return store

func _beam() -> Part:
    return preload("res://assets/parts/beam/beam.tres")   # 6x2x2 Wood


func test_part_imprints_solid_voxels_with_material() -> void:
    var store := _store()
    # Place the beam in open air (above the surface); execute regardless of attach so we pin
    # the imprint itself. Sample the beam's CENTRE (bottom at pos.y, 2 m tall -> +1 m).
    var pos := Vector3(COLUMN_X, _surface() + 20.0, COLUMN_Z)
    ConstructionAction.new(_beam(), pos, Vector3.ZERO, &"Wood", store, null).execute()
    var centre := Vector3(COLUMN_X, _surface() + 21.0, COLUMN_Z)
    assert_lt(store.sample(centre), 0.0, "the beam imprinted solid into the store")
    assert_eq(store.material_at(centre), MaterialPalette.index_of(&"Wood"), "with the part's material")


func test_part_resting_on_ground_validates() -> void:
    var store := _store()
    var pos := Vector3(COLUMN_X, _surface(), COLUMN_Z)   # bottom at the surface
    assert_true(ConstructionAction.new(_beam(), pos, Vector3.ZERO, &"Wood", store, null).validate(),
        "a beam resting on the ground attaches")


func test_floating_part_is_refused() -> void:
    var store := _store()
    var pos := Vector3(COLUMN_X, _surface() + 15.0, COLUMN_Z)   # well up in the air
    assert_false(ConstructionAction.new(_beam(), pos, Vector3.ZERO, &"Wood", store, null).validate(),
        "a part floating in air is refused")
