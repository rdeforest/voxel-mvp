extends GutTest

# The imprint write-API: stamps COMBINE with the existing field (terrain and parts are
# one field). Union adds solid; subtract carves; terrain material is kept where the
# stamp doesn't add. Tested with CLOSED shapes so watertightness is the right invariant
# (a flat ground would be an open surface — boundary edges at the domain walls are
# expected, not a bug).

const LEAF := 0.5


func _sphere(c: Vector3, r: float) -> Callable:
    return func(p: Vector3) -> float: return p.distance_to(c) - r

func _boundary_edges(idx: PackedInt32Array) -> int:
    var counts := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
            var k := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[k] = counts.get(k, 0) + 1
    var b := 0
    for k in counts:
        if counts[k] == 1:
            b += 1
    return b


func test_union_merges_two_solids_watertight() -> void:
    var t := VoxelOctree.new(Vector3.ZERO, 16.0)
    t.imprint(_sphere(Vector3(8, 8, 8), 4.0), LEAF, 1)          # solid A, material 1
    t.stamp(_sphere(Vector3(11, 8, 8), 2.0), LEAF, 2, VoxelOctree.Op.UNION)   # add B (fully in box)

    assert_lt(t.sample(Vector3(8, 8, 8)), 0.0, "A's interior still solid")
    assert_eq(t.material_at(Vector3(8, 8, 8)), 1, "A keeps its material")
    assert_lt(t.sample(Vector3(12.5, 8, 8)), 0.0, "B's interior is now solid (added)")
    assert_eq(t.material_at(Vector3(12.5, 8, 8)), 2, "B-only region wears the stamp material")
    assert_eq(_boundary_edges(OctreeMesher.mesh(t).indices), 0, "the merged blob is watertight")


func test_subtract_carves_an_internal_cavity_watertight() -> void:
    var t := VoxelOctree.new(Vector3.ZERO, 16.0)
    t.imprint(_sphere(Vector3(8, 8, 8), 4.0), LEAF, 1)
    t.stamp(_sphere(Vector3(8, 8, 8), 1.5), LEAF, 0, VoxelOctree.Op.SUBTRACT)  # hollow out the core

    assert_gt(t.sample(Vector3(8, 8, 8)), 0.0, "the carved core is now air")
    assert_lt(t.sample(Vector3(5.5, 8, 8)), 0.0, "the shell between cavity and surface stays solid")
    assert_eq(_boundary_edges(OctreeMesher.mesh(t).indices), 0, "outer shell + inner cavity, both closed")
