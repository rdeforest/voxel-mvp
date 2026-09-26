extends GutTest

# edit-store-noop-write-reports-changed: does a lattice that is the store's own field (lattice_writes
# false) report `changed`, and by how much do the leaves it re-represents move? Three kinds of leaf:
# a coarse edited leaf, an inherited 1 m leaf a previous write left around itself, and the padded
# leaves of a stamp the brush doesn't reach.
# Run: bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/dev/probe_noop_write_changed.gd

var _surface: float


func before_all() -> void:
    _surface = EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


func test_probe() -> void:
    for leaf_size: float in [2.0, 4.0]:
        var st   := _stamped(leaf_size)
        var leaf := _leaf(leaf_size)
        _report("coarse %s m leaf" % leaf_size, st, leaf)

    # A shifted first write leaves the field discontinuous across its lower faces (a write doesn't
    # blend with its neighbours), so the leaf below it is probed after an unshifted one.
    for probe: Array in [[Vector3(3, 1, 1), -0.3], [Vector3.ZERO, 0.0]]:
        var st   := _stamped(4.0)
        var leaf := _leaf(4.0)
        var lo   := leaf + Vector3.ONE
        st.write_region(_own_lattice(st, lo, probe[1]), PackedByteArray(), 3, lo, 1.0)
        _report("inherited 1 m leaf at leaf+%s after a %s shift" % probe, st, leaf + probe[0])

    _probe_stamp_padding()
    pass_test("probe")


# A stamp's padded leaves: how many points inside its region box, beyond brush reach, move.
func _probe_stamp_padding() -> void:
    var st     := _stamped(4.0)
    var lo     := _leaf(4.0) + Vector3.ONE
    var centre := lo + Vector3.ONE
    var points := []
    for z in 9:
        for y in 9:
            for x in 9:
                var p := lo + Vector3(x, y, z) * 0.25
                if p.distance_to(centre) > 0.4 + 0.5:
                    points.append(p)

    var before := points.map(func(p: Vector3) -> float: return st.sample(p))
    st.stamp_sphere(centre, 0.4, VoxelConstants.STORE_OP_SUBTRACT, 0, 0.5)
    var moved := 0
    var worst := 0.0
    for i in points.size():
        var d := absf(st.sample(points[i]) - before[i])
        if d > 0.0:
            moved += 1
            worst = maxf(worst, d)

    gut.p("stamp padding: %d/%d points beyond brush reach moved, worst %s" % [moved, points.size(), worst])


func _leaf(leaf_size: float) -> Vector3:
    return Vector3(100.0, floorf(_surface / leaf_size) * leaf_size, 100.0)


func _stamped(leaf_size: float) -> EditStore:
    var manager := EditStoreManager.new()
    manager.setup()
    var st := manager.store
    st.stamp_box(_leaf(leaf_size) + Vector3.ONE * 2.2, Vector3(2.5, 3.0, 1.7), 0, 3, leaf_size)
    return st


func _own_lattice(st: EditStore, lo: Vector3, shift: float) -> PackedFloat32Array:
    var sdf := PackedFloat32Array()
    for z in 3:
        for y in 3:
            for x in 3:
                sdf.append(st.sample(lo + Vector3(x, y, z)) + shift)

    return sdf


# Writes the store's own field as a 1 m lattice over the 1 m leaf at `lo` and reports what moved in it.
func _report(label: String, st: EditStore, lo: Vector3) -> void:
    var sdf    := _own_lattice(st, lo, 0.0)
    var writes := st.lattice_writes(sdf, 3, lo, 1.0)
    var points := []
    for z in 9:
        for y in 9:
            for x in 9:
                points.append(lo + Vector3(x, y, z) * 0.125)

    var before := points.map(func(p: Vector3) -> float: return st.sample(p))
    var got: Dictionary = st.write_region_flips(sdf, PackedByteArray(), 3, lo, 1.0)
    var moved := 0
    var worst := 0.0
    for i in points.size():
        var d := absf(st.sample(points[i]) - before[i])
        if d > 0.0:
            moved += 1
            worst = maxf(worst, d)

    var again: Dictionary = st.write_region_flips(sdf, PackedByteArray(), 3, lo, 1.0)
    gut.p("%s: lattice_writes=%s changed=%s moved %d/%d worst %s; repeat changed=%s"
        % [label, writes, got.changed, moved, points.size(), worst, again.changed])
