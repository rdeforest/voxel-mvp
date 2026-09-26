extends RefCounted

# The store the preview-prediction gates (test_edit_store_predict, test_construction_attach_predict)
# compare the game against the oracle on: the game's own (EditStoreManager: the real TerrainField
# generator) under a multi-level edit history — edited leaves at 2 m, 1 m, 0.5 m and 0.25 m beside
# unedited generator ground — so lattice points land on stored corners, trilerps inside finer
# leaves, and the generator itself. A raw analytic field would hide every one of those paths.
# (Drafted by Claude, overnight 2026-09-26; lifted out of test_edit_store_predict unchanged.)

const Oracle := preload("res://test/support/lattice_oracle.gd")

var store:   EditStore
var base:    Vector3   # the edited column's surface point, floored to the 2 m leaf grid
var surface: float     # the generator's surface height there (fractional)


func _init() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    store   = manager.store
    surface = EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    base    = Vector3(100.0, floorf(surface / 2.0) * 2.0, 100.0)
    _edit_history()


# Earlier edits at four leaf sizes, overlapping each other and the positions under test.
func _edit_history() -> void:
    var s := Vector3(100.0, surface, 100.0)
    store.stamp_box(s + Vector3(3.0, 0.0, -2.0), Vector3(6.0, 4.0, 6.0), VoxelConstants.STORE_OP_UNION, 3, 2.0)
    store.stamp_sphere(s + Vector3(-2.0, 0.3, 1.0), 2.5, VoxelConstants.STORE_OP_SUBTRACT, 0, 1.0)
    store.stamp_sphere(s + Vector3(1.0, -0.5, 2.0), 1.6, VoxelConstants.STORE_OP_UNION, 2, 0.5)
    store.stamp_sphere(s + Vector3(0.3, 0.7, -0.4), 1.1, VoxelConstants.STORE_OP_SUBTRACT, 0, 0.25)
    Oracle.sphere_stamp(store, s + Vector3(-1.2, 1.4, -1.7), 1.3, VoxelConstants.STORE_OP_UNION,
        VoxelConstants.RENDER_BASE_CELL).write(store, PackedByteArray())


# Cell/leaf corners (1 m, 2 m, 0.5 m, 0.25 m), cell centres, generic points, the fractional
# surface, and one well above it (where a dig writes nothing).
func positions() -> Array[Vector3]:
    var s := Vector3(100.0, surface, 100.0)
    return [
        base,
        base + Vector3(0.5, 0.5, 0.5),
        base + Vector3(0.25, 0.75, 0.5),
        base + Vector3(1.0, 0.0, -1.0),
        base + Vector3(2.0, 2.0, -2.0),
        base + Vector3(0.37, 0.61, 0.13),
        base + Vector3(-2.5, 1.0, 1.5),
        s,
        s + Vector3(0.0, 1.3, 0.0),
        s + Vector3(0.0, -1.1, 0.0),
        s + Vector3(3.0, 0.0, -2.0),
        s + Vector3(0.0, 12.0, 0.0),
    ]
