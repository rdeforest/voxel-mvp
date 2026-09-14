extends GutTest

# Phase B S5: terrain actions write the EditStore directly (no godot_voxel, no dual-write).
# Pins the action -> store contract headlessly — the class of bug that the lossy godot_voxel
# round-trip used to introduce ("persists but doesn't match the edit"). Each action's exact
# computed field must land in the store.

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
    # Integer-aligned root (like production's EditStoreManager.ROOT_ORIGIN) so the size-1
    # leaf grid coincides with the integer edit-cell grid — a fractional root would offset
    # the leaves and smear edits written at integer coordinates.
    var store := EditStore.new()
    store.setup(Vector3(-128.0, -128.0, -128.0), 256.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return store

func _ctx(store: EditStore, player: CharacterBody3D = null) -> ActionContext:
    return ActionContext.new(store, player, null)


func test_dig_carves_solid_to_air() -> void:
    var store := _store()
    var center := Vector3(COLUMN_X, _surface() - 5.0, COLUMN_Z)
    assert_lt(store.sample(center), 0.0, "below the surface is solid before the dig")
    DigAction.new(center, 3.0, _ctx(store)).execute()
    assert_gt(store.sample(center), 0.0, "the dig carved the centre to air in the store")


func test_fill_adds_solid_and_paints_material() -> void:
    var store := _store()
    var center := Vector3(COLUMN_X, _surface() + 10.0, COLUMN_Z)
    assert_gt(store.sample(center), 0.0, "above the surface is air before the fill")
    FillAction.new(center, 3.0, _ctx(store), &"Stone").execute()
    assert_lt(store.sample(center), 0.0, "the fill made the centre solid in the store")
    assert_eq(store.material_at(center), MaterialPalette.index_of(&"Stone"), "fill painted its material")


func test_fill_voxel_sets_one_solid_cell() -> void:
    var store := _store()
    var cell := Vector3i(int(COLUMN_X), int(_surface()) + 8, int(COLUMN_Z))
    var action := FillVoxelAction.new(cell, _ctx(store), &"Stone")
    assert_true(action.validate(), "an air cell can be filled")
    action.execute()
    assert_lt(store.sample(Vector3(cell)), 0.0, "the cell is solid in the store")
    assert_eq(store.material_at(Vector3(cell)), MaterialPalette.index_of(&"Stone"), "the cell carries its material")


func test_empty_voxel_clears_one_solid_cell() -> void:
    var store := _store()
    var cell := Vector3i(int(COLUMN_X), int(_surface()) - 6, int(COLUMN_Z))
    var action := EmptyVoxelAction.new(cell, _ctx(store))
    assert_true(action.validate(), "a solid cell can be emptied")
    action.execute()
    assert_gt(store.sample(Vector3(cell)), 0.0, "the cell is air in the store")


func test_dig_then_fill_returns_to_solid() -> void:
    # Re-editing the same region must combine with the STORED value, not re-derive from the
    # generator (the dual-write bug). Carve to air, fill it back, expect solid again.
    var store := _store()
    var center := Vector3(COLUMN_X, _surface() - 5.0, COLUMN_Z)
    DigAction.new(center, 4.0, _ctx(store)).execute()
    assert_gt(store.sample(center), 0.0, "carved to air")
    FillAction.new(center, 3.0, _ctx(store), &"Stone").execute()
    assert_lt(store.sample(center), 0.0, "filled back to solid")
