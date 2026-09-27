extends SceneTree
func _initialize() -> void:
    for r in [0.0, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 40.0, 70.0, 100.0]:
        var h := func(x: float, z: float) -> float:
            return EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
        var x: float = r * 0.78
        var z: float = r * 0.62
        var e := 0.25
        var gx: float = (h.call(x + e, z) - h.call(x - e, z)) / (2 * e)
        var gz: float = (h.call(x, z + e) - h.call(x, z - e)) / (2 * e)
        print("r=%5.1f h=%7.2f slope=%5.1f deg" % [r, h.call(x, z), rad_to_deg(atan(sqrt(gx * gx + gz * gz)))])
    quit()
