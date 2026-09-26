extends GutTest

# misc-low-severity item 7: where EditStore.lattice_turns_in's point tests disagree with the
# truth. Cases in the air far above the terrain, on 1 m leaves the probe writes itself.
# Run: bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/dev/probe_turns_in_exactness.gd
# (Drafted by Claude, overnight 2026-09-26.)

const Y := 500.0

var _store: EditStore


func before_each() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store = manager.store


# A lattice whose value depends on y only: `rows[j]` at lattice row j.
func _rows_lattice(origin: Vector3, rows: Array) -> SdfLattice:
    var lat := SdfLattice.new(origin, 1.0, rows.size())
    for z in lat.dim:
        for y in lat.dim:
            for x in lat.dim:
                lat.sdf[lat.index(Vector3i(x, y, z))] = rows[y]
    return lat


func _write(lat: SdfLattice) -> void:
    _store.write_region(lat.sdf, PackedByteArray(), lat.dim, lat.origin, lat.cell)


func test_sliver_between_tested_points() -> void:
    _write(_rows_lattice(Vector3(0, Y, 0), [-0.1, 0.9]))
    var lat := _rows_lattice(Vector3(0, Y, 0), [-0.3, 0.7])
    var box := AABB(Vector3(0.05, Y + 0.05, 0.05), Vector3(0.9, 0.9, 0.9))
    var p   := Vector3(0.5, Y + 0.2, 0.5)
    print("sliver: prior at y+0.2 = %f, written there = %f" % [_store.sample(p), lat.value_at(p)])
    print("sliver: solidifies_in = %s (truth: true)" % lat.solidifies_in(_store, box))
    _write(_rows_lattice(Vector3(0, Y, 0), [0.1, 1.1]))
    var carve := _rows_lattice(Vector3(0, Y, 0), [0.3, 1.3])
    print("sliver air: empties_in = %s (truth: true)" % carve.empties_in(_store, box))
    pass_test("printed")


func test_discontinuous_prior_at_box_max_face() -> void:
    _write(_rows_lattice(Vector3(0, Y, 0), [-1.0, -1.0]))
    _write(_rows_lattice(Vector3(0, Y + 1.0, 0), [1.0, 1.0]))
    var lat := _rows_lattice(Vector3(0, Y, 0), [-1.0, -1.0, 1.0])
    var box := AABB(Vector3(0.2, Y + 0.2, 0.2), Vector3(0.6, 0.8, 0.6))
    print("face: prior just below the face %f, at the face %f" % [
        _store.sample(Vector3(0.5, Y + 0.999, 0.5)), _store.sample(Vector3(0.5, Y + 1.0, 0.5))])
    print("face: solidifies_in = %s (truth inside the box's leaf: false)" % lat.solidifies_in(_store, box))
    pass_test("printed")
