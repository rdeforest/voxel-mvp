extends GutTest

# The "does this write change anything" flag every predicted lattice carries (SdfLattice.writes),
# which CsgAction refuses on. It must be the answer for the write itself: false exactly when
# write_region would leave every stored leaf corner as it is. The false-change case this pins is
# sdf-lattice-writes-false-change-at-max-faces (fixed in af19749): a lattice point on the region's
# max faces was compared against store.sample, which reads the neighbouring leaf the write doesn't
# touch. The store is the game's own (EditStoreManager: aligned root, the real generator).

var _store: EditStore
var _air:   Vector3   # a point far enough above the surface that the terrain SDF exceeds SDF_AIR


func before_each() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store = manager.store
    var surface := EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    _air = Vector3(100.0, floorf(surface) + 40.0, 100.0)


func _ctx() -> ActionContext:
    return ActionContext.new(_store, null, null)


func _shapes() -> Dictionary:
    return {
        "sphere":      [CsgSphereShape.new(2.0), Transform3D(Basis(), _air)],
        "rotated box": [CsgBoxShape.new(Vector3(3.0, 1.5, 2.0)),
            Transform3D(Basis(Vector3(1.0, 1.0, 0.0).normalized(), 0.6), _air + Vector3(0.3, 0.2, 0.7))],
        "cylinder":    [CsgCylinderShape.new(1.2, 3.0), Transform3D(Basis(), _air + Vector3(0.5, 0.0, 0.5))],
    }


func _assert_region_in_deep_air(lat: SdfLattice) -> void:
    assert_gt(_store.sample(lat.region_hi), VoxelConstants.SDF_AIR,
        "the terrain SDF past the region's max corner exceeds SDF_AIR (else this tests nothing)")


func test_identical_csg_add_in_air_is_refused() -> void:
    for label: String in _shapes():
        var shape: CsgShape      = _shapes()[label][0]
        var xform: Transform3D   = _shapes()[label][1]
        var first := CsgAction.new(shape, xform, CsgState.Op.ADD, &"Stone", _ctx())
        _assert_region_in_deep_air(VoxelImprint.lattice(_store, shape, xform, CsgState.Op.ADD))
        assert_true(first.validate(), "%s: the first stamp writes" % label)
        first.execute()
        var again := CsgAction.new(shape, xform, CsgState.Op.ADD, &"Stone", _ctx())
        assert_false(again.validate(), "%s: the identical re-stamp is a no-op, refused" % label)
        assert_true(again.preview().refused, "%s: and previewed refused" % label)


# The re-stamp's dry run runs over the edited leaves the first stamp left, sharing each lattice
# point between them; any one changed point must still be found.
func test_one_changed_point_over_a_restamp_in_air_writes() -> void:
    var shape := CsgSphereShape.new(2.0)
    var xform := Transform3D(Basis(), _air)
    CsgAction.new(shape, xform, CsgState.Op.ADD, &"Stone", _ctx()).execute()
    var lat := VoxelImprint.lattice(_store, shape, xform, CsgState.Op.ADD)
    assert_false(lat.writes, "the identical re-stamp writes nothing (else this tests nothing)")
    var mid := floori(lat.dim / 2.0)
    for at: Vector3i in [Vector3i.ZERO, Vector3i(mid, mid, mid), Vector3i(lat.dim - 1, mid, 0), Vector3i.ONE * (lat.dim - 1)]:
        var nudged := lat.sdf.duplicate()
        nudged[lat.index(at)] = nudged[lat.index(at)] + 0.5
        assert_true(_store.lattice_writes(nudged, lat.dim, lat.origin, lat.cell), "nudging point %s is a write" % at)


func test_identical_sphere_stamp_writes_nothing() -> void:
    for op in [VoxelConstants.STORE_OP_UNION, VoxelConstants.STORE_OP_SUBTRACT]:
        var center := _air + Vector3(0.0, -40.0, 0.0) + Vector3(0.3, 0.1, -0.2)
        var lat    := SdfLattice.sphere_stamp(_store, center, 2.5, op, VoxelConstants.RENDER_BASE_CELL)
        assert_true(lat.writes, "op %d: the first stamp at the surface writes" % op)
        lat.write(_store, PackedByteArray())
        assert_false(SdfLattice.sphere_stamp(_store, center, 2.5, op, VoxelConstants.RENDER_BASE_CELL).writes,
            "op %d: the identical re-stamp writes nothing" % op)


# The imprint's region, stored as `interior` everywhere but the x max-face plane, which holds
# `face`; the brush (a unit sphere at the region's centre) reaches that plane at distance ~3.
func _crafted_region(interior: float, face: float) -> SdfLattice:
    var shape := CsgSphereShape.new(1.0)
    var lat   := VoxelImprint.lattice(_store, shape, Transform3D(Basis(), _air), CsgState.Op.ADD)
    for z in lat.dim:
        for y in lat.dim:
            for x in lat.dim:
                lat.sdf[lat.index(Vector3i(x, y, z))] = face if x == lat.dim - 1 else interior
    lat.write(_store, PackedByteArray())
    return lat


func _face_centre(lat: SdfLattice) -> Vector3i:
    return Vector3i(lat.dim - 1, floori(lat.dim / 2.0), floori(lat.dim / 2.0))


# The other direction: a stamp whose only change is to values the region's max-face leaves own
# still counts as a write.
func test_change_only_at_a_max_face_counts() -> void:
    var stored := _crafted_region(VoxelConstants.SDF_SOLID, VoxelConstants.SDF_AIR)
    _assert_region_in_deep_air(stored)
    var lat := VoxelImprint.lattice(_store, CsgSphereShape.new(1.0), Transform3D(Basis(), _air), CsgState.Op.ADD)
    var changed: Array[Vector3i] = []
    for z in lat.dim:
        for y in lat.dim:
            for x in lat.dim:
                var i := Vector3i(x, y, z)
                if lat.sdf[lat.index(i)] != stored.sdf[stored.index(i)]:
                    changed.append(i)
    assert_gt(changed.size(), 0, "the brush reaches the max face (else this tests nothing)")
    assert_true(changed.all(func(i: Vector3i) -> bool: return i.x == lat.dim - 1),
        "and changes nothing else")
    assert_true(lat.writes, "a change only at max-face-owned values is a write")


# A union never raises a stored value: at the max face the brush combines with the value the
# rewritten leaf holds there, not the neighbouring leaf's (which the write leaves alone).
func test_union_combines_with_the_owned_max_face_value() -> void:
    var stored := _crafted_region(VoxelConstants.SDF_SOLID, 1.0)
    var at     := _face_centre(stored)
    assert_gt(_store.sample(stored.point(at)), VoxelConstants.SDF_AIR,
        "the neighbouring leaf reads deep air there (else this tests nothing)")
    var lat := VoxelImprint.lattice(_store, CsgSphereShape.new(1.0), Transform3D(Basis(), _air), CsgState.Op.ADD)
    assert_eq(lat.sdf[lat.index(at)], 1.0, "the owned 1.0 is kept, not raised to the brush's distance")
    assert_false(lat.writes, "and the stamp changes nothing the store holds")


# A seam inside the region: an earlier write left the leaves below x = seam holding a different
# value there than the leaves above it. Every lattice point matches the leaf store.sample reads it
# from (the upper one), yet writing the lattice replaces the lower leaves' corners: a write.
func test_seam_inside_the_region_counts() -> void:
    var o    := Vector3(floorf(_air.x), floorf(_air.y), floorf(_air.z))
    var dim  := 6
    var base := PackedFloat32Array()
    base.resize(dim * dim * dim)
    base.fill(3.0)
    _store.write_region(base, PackedByteArray(), dim, o, 1.0)
    var low := PackedFloat32Array()
    low.resize(27)
    low.fill(3.0)
    for i in 9:
        low[2 + 3 * i] = 4.0                                   # the x = 2 plane: its max face
    _store.write_region(low, PackedByteArray(), 3, o, 1.0)
    var seam := o + Vector3(2.0, 1.0, 1.0)
    assert_eq(_store.sample(seam), 3.0, "store.sample reads the upper leaf at the seam")
    assert_eq(_store.sample_toward(seam, seam + Vector3(-0.5, 0.5, 0.5)), 4.0, "the lower leaf holds 4 there")
    assert_eq(_store.sample(seam), _store.sample_toward(seam, seam), "sample is sample_toward itself")
    assert_true(_store.lattice_writes(base, dim, o, 1.0), "re-writing the uniform field heals the seam: a write")
    var lat := StoreWrite.lattice(_store, [LatticeEdit.new(Vector3i(seam), _store.sample(seam), 0)] as Array[LatticeEdit])
    assert_true(lat.writes, "so a work write over it, setting its point to its own value, writes")
    low.fill(3.0)
    _store.write_region(low, PackedByteArray(), 3, o, 1.0)
    assert_false(_store.lattice_writes(base, dim, o, 1.0), "once healed, the uniform field writes nothing")


# Leaves finer than the write's cell (an earlier finer edit) are rewritten from the lattice's
# trilerp, which flattens their detail even where every lattice point already matches.
func test_flattening_finer_leaves_counts() -> void:
    var center := _air + Vector3(0.4, 0.3, 0.6)
    _store.stamp_sphere(center, 0.8, VoxelConstants.STORE_OP_UNION, 1, 0.25)
    var at  := Vector3i(center.round())
    var lat := StoreWrite.lattice(_store, [LatticeEdit.new(at, _store.sample(Vector3(at)), 0)] as Array[LatticeEdit])
    assert_true(lat.writes, "a no-op-looking lattice over quarter-metre sphere detail writes")


# A leaf coarser than the cell is subdivided before it is written; a lattice that is that leaf's own
# trilerp reproduces the children the subdivision makes, so nothing changes.
func test_reproducing_a_coarser_leaf_writes_nothing() -> void:
    var center := Vector3(floorf(_air.x / 2.0) * 2.0, floorf(_air.y / 2.0) * 2.0, floorf(_air.z / 2.0) * 2.0)
    _store.stamp_box(center, Vector3(3.0, 3.0, 3.0), VoxelConstants.STORE_OP_UNION, 1, 2.0)
    var at  := Vector3i(center) + Vector3i(1, 0, 1)
    var lat := StoreWrite.lattice(_store, [LatticeEdit.new(at, _store.sample(Vector3(at)), 0)] as Array[LatticeEdit])
    assert_true(_store.has_edit(Vector3(at)), "the point sits in the 2 m edited leaves (else this tests nothing)")
    assert_false(lat.writes, "re-writing the 2 m leaves' own field at 1 m writes nothing")
    var nudged := lat.sdf.duplicate()
    var mid    := lat.index(Vector3i(2, 2, 2))
    nudged[mid] = nudged[mid] + 0.5
    assert_true(_store.lattice_writes(nudged, lat.dim, lat.origin, lat.cell), "and nudging one point is a write")


# The dry run over unedited ground (lattice_writes shares each lattice point's generator value
# between the up-to-eight leaves meeting there): deep enough that the brush wins nowhere, a union
# changes nothing, and any one changed point is still found, whichever leaf reaches it first.
func _buried() -> Transform3D:
    return Transform3D(Basis(), _air + Vector3(0.0, -80.0, 0.0))


# The store's own value at every lattice point, rounded to float32 as a lattice holds it.
func _ground(lat: SdfLattice) -> PackedFloat32Array:
    var ground := PackedFloat32Array()
    ground.resize(lat.sdf.size())
    for z in lat.dim:
        for y in lat.dim:
            for x in lat.dim:
                ground[lat.index(Vector3i(x, y, z))] = _store.sample(lat.point(Vector3i(x, y, z)))

    return ground


func test_union_buried_in_ground_is_refused() -> void:
    var shape := CsgSphereShape.new(3.0)
    var lat   := VoxelImprint.lattice(_store, shape, _buried(), CsgState.Op.ADD)
    assert_false(_store.has_edit(lat.origin + (lat.region_hi - lat.origin) * 0.5), "the ground there is unedited")
    assert_eq(lat.sdf, _ground(lat), "the lattice is the ground's own field: the brush wins nowhere (else this tests nothing)")
    assert_false(lat.writes, "a union into deep ground writes nothing")
    assert_true(CsgAction.new(shape, _buried(), CsgState.Op.ADD, &"Stone", _ctx()).preview().refused, "so it previews refused")


func test_one_changed_point_in_unedited_ground_writes() -> void:
    var lat := VoxelImprint.lattice(_store, CsgSphereShape.new(3.0), _buried(), CsgState.Op.ADD)
    var mid := floori(lat.dim / 2.0)
    for at: Vector3i in [Vector3i.ZERO, Vector3i(mid, mid, mid), Vector3i(lat.dim - 1, mid, 0), Vector3i.ONE * (lat.dim - 1)]:
        var nudged := lat.sdf.duplicate()
        nudged[lat.index(at)] = nudged[lat.index(at)] + 0.5
        assert_true(_store.lattice_writes(nudged, lat.dim, lat.origin, lat.cell), "nudging point %s is a write" % at)


# An edited leaf and unedited ones meet at a point where the unedited leaves keep the generator's
# value and the edited leaf holds another. The unedited leaf below it on x is reached first; its
# finding (unchanged) must not stand for the edited leaf.
func test_edited_leaf_beside_unedited_ones_is_compared_on_its_own() -> void:
    var lat    := VoxelImprint.lattice(_store, CsgSphereShape.new(3.0), _buried(), CsgState.Op.ADD)
    var ground := _ground(lat)
    assert_false(_store.lattice_writes(ground, lat.dim, lat.origin, lat.cell), "the generator's own values write nothing")
    var at   := lat.point(Vector3i.ONE * floori(lat.dim / 2.0))
    var leaf := PackedFloat32Array()
    for i in 8:
        leaf.append(_store.sample(at + Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1) * lat.cell))
    leaf[0] = leaf[0] + 0.5
    _store.write_region(leaf, PackedByteArray(), 2, at, lat.cell)
    assert_true(_store.has_edit(at + Vector3.ONE * lat.cell * 0.5), "the leaf at the point is edited")
    assert_false(_store.has_edit(at - Vector3(0.5, -0.5, -0.5) * lat.cell), "and the one below it on x is not")
    assert_true(_store.lattice_writes(ground, lat.dim, lat.origin, lat.cell),
        "writing the generator's values restores the edited leaf's corner: a write")
