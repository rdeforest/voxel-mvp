extends GutTest

# The palette is the single source of truth tying a per-voxel material id to a
# name and an albedo. Index 0 is natural (slope-shaded, never looked up for colour).

func test_natural_is_zero() -> void:
    assert_eq(MaterialPalette.NATURAL, 0)
    assert_eq(MaterialPalette.NAMES[0], &"Natural")


func test_index_roundtrip() -> void:
    for i in range(1, MaterialPalette.NAMES.size()):
        assert_eq(MaterialPalette.index_of(MaterialPalette.NAMES[i]), i, "name->index->name")
    assert_eq(MaterialPalette.index_of(&"NoSuchMaterial"), MaterialPalette.NATURAL, "unknown -> natural")


func test_selectable_excludes_natural() -> void:
    var sel := MaterialPalette.selectable()
    assert_false(sel.has(&"Natural"), "Natural is not user-selectable")
    assert_eq(sel.size(), MaterialPalette.NAMES.size() - 1)


func test_colors_align_with_names() -> void:
    var cols := MaterialPalette.colors()
    assert_eq(cols.size(), MaterialPalette.NAMES.size(), "one colour per name")
    # A real material's colour is its Materials albedo.
    var stone_i := MaterialPalette.index_of(&"Stone")
    assert_eq(cols[stone_i], Materials.from_name(&"Stone").albedo)
