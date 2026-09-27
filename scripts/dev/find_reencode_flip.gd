extends SceneTree

# Where does re-encoding predict_carve's box (the current field at the corners) flip a cell the plan
# didn't name, and in which direction? Scans r=1.4 surface plans on the game's field. Flips to solid
# are rare: none within 20 m of the origin, so the scan reaches 80 m.
#   bin/godot --path . --headless -s scripts/dev/find_reencode_flip.gd


const HALF := 80


func _initialize() -> void:
    var m := EditStoreManager.new()
    m.setup()
    var store := m.store
    var found := 0
    var solid_found := 0
    for i in 2 * HALF:
        for j in 2 * HALF:
            var x := float(i - HALF)
            var z := float(j - HALF)
            var top := EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP,
                EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
            var center := Vector3(x + 0.5, top, z + 0.5)
            var plan: Array[Vector3i] = []
            for cell in VoxelUtils.cells_in_sphere(center, 1.4):
                if store.sample(Vector3(cell) + Vector3(0.5, 0.5, 0.5)) < 0.0:
                    plan.append(cell)
            if plan.is_empty():
                continue
            var d := store.predict_carve(plan)
            if not d.has("sdf"):
                print("REFUSED at ", center, " ", d)
                continue
            var plain := store.fill_region(Vector3i(d.origin), d.dim, 1.0, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO)
            var flips := store.lattice_flips(plain, d.dim, d.origin, 1.0)
            var n: int = flips.air.size() + flips.solid.size()
            if not flips.solid.is_empty():
                solid_found += 1
                if solid_found <= 5:
                    print("SOLID x=%d z=%d  solid %s" % [x, z, flips.solid])
            if n > 0:
                found += 1
                if found <= 5:
                    print("x=%d z=%d  flips %d (air %s solid %s)" % [x, z, n, flips.air, flips.solid])
    print("spots with a re-encoding flip: ", found, " of ", 4 * HALF * HALF, ", to solid at ", solid_found)
    quit()
