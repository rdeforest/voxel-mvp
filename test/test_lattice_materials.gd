extends GutTest

# SdfLattice.materials(): a leaf takes the edit's material only where the edit made one of its
# corners solid. "Made" compares against the value the rewritten leaf held at each lattice point —
# the owner leaf the C++ builders read "before" from (SdfLattice.owner_centre) — not store.sample,
# which on the region's max faces reads the neighbouring leaf the write leaves alone. At a seam
# there (the owner leaf solid, the neighbour air) the old read repainted leaves the brush never
# reached. The store is the game's own (EditStoreManager: aligned root, the real generator).
# (Drafted by Claude, overnight 2026-09-26.)

const KEPT := &"Wood"
const FILL := &"Stone"

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


# Store `lat`'s region as air everywhere but its x max-face plane, which is solid, every leaf
# painted KEPT: the leaves at x = dim - 2 hold solid on that face, the unedited leaves beyond it
# the generator's deep air — a seam on the region's max face.
func _seam_at_max_x(lat: SdfLattice) -> void:
    var sdf := PackedFloat32Array()
    sdf.resize(lat.dim * lat.dim * lat.dim)
    var indices := PackedByteArray()
    indices.resize(sdf.size())
    indices.fill(MaterialPalette.index_of(KEPT))
    for z in lat.dim:
        for y in lat.dim:
            for x in lat.dim:
                var face := x == lat.dim - 1
                sdf[lat.index(Vector3i(x, y, z))] = VoxelConstants.SDF_SOLID if face else VoxelConstants.SDF_AIR
    _store.write_region(sdf, indices, lat.dim, lat.origin, lat.cell)

    var probe := Vector3i(lat.dim - 1, floori(lat.dim / 2.0), floori(lat.dim / 2.0))
    var face  := lat.point(probe)
    assert_gt(_store.sample(face), VoxelConstants.SDF_AIR,
        "store.sample reads the neighbouring leaf's deep air on the face (else this tests nothing)")
    assert_lt(_store.sample_toward(face, lat.owner_centre(probe)), VoxelConstants.SDF_SOLID_THRESHOLD,
        "the owner leaf holds solid there")


# The seam sits on the action's max face only if the action writes the lattice the seam was built
# from; guards the tests against the action's region drifting away from the test's.
func _assert_same_region(action_lat: SdfLattice, lat: SdfLattice, label: String) -> void:
    assert_eq([action_lat.origin, action_lat.cell, action_lat.dim], [lat.origin, lat.cell, lat.dim],
        "%s: the action writes the seam's lattice (else this tests nothing)" % label)


# The face leaves (x = dim - 2), which the brush never reaches, keep KEPT; the leaf at the brush's
# centre takes FILL.
func _assert_face_leaves_kept(lat: SdfLattice, label: String) -> void:
    var repainted: Array[Vector3i] = []
    for z in lat.dim - 1:
        for y in lat.dim - 1:
            var leaf := Vector3i(lat.dim - 2, y, z)
            var centre := lat.point(leaf) + Vector3.ONE * (lat.cell * 0.5)
            if _store.material_at(centre) != MaterialPalette.index_of(KEPT):
                repainted.append(leaf)
    assert_eq(repainted, [] as Array[Vector3i], "%s: no max-face leaf is repainted" % label)
    var mid := lat.point(Vector3i.ONE * floori((lat.dim - 1) / 2.0)) + Vector3.ONE * (lat.cell * 0.5)
    assert_eq(_store.material_at(mid), MaterialPalette.index_of(FILL),
        "%s: the brush's own leaf takes its material" % label)


func test_fill_keeps_the_material_of_a_max_face_seam() -> void:
    var centre := _air + Vector3(0.3, 0.1, -0.2)
    var fill   := FillAction.new(centre, 2.0, _ctx(), FILL)
    var lat    := SdfLattice.sphere_stamp(_store, centre, 2.0, VoxelConstants.STORE_OP_UNION,
        VoxelConstants.RENDER_BASE_CELL)
    _seam_at_max_x(lat)
    assert_true(fill.validate(), "the fill writes (else this tests nothing)")
    _assert_same_region(fill._stamp(), lat, "fill")
    fill.execute()
    _assert_face_leaves_kept(lat, "fill")


func test_imprint_keeps_the_material_of_a_max_face_seam() -> void:
    var shape := CsgSphereShape.new(1.0)
    var xform := Transform3D(Basis(), _air + Vector3(0.3, 0.1, -0.2))
    var lat   := VoxelImprint.lattice(_store, shape, xform, CsgState.Op.ADD)
    _seam_at_max_x(lat)
    var csg := CsgAction.new(shape, xform, CsgState.Op.ADD, FILL, _ctx())
    assert_true(csg.validate(), "the imprint writes (else this tests nothing)")
    _assert_same_region(csg._lattice, lat, "imprint")
    csg.execute()
    _assert_face_leaves_kept(lat, "imprint")
