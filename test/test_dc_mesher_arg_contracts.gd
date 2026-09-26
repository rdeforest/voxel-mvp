extends GutTest

# DCOctreeMesher entry-point preconditions (trap 1 of the fixed bug dc-mesher-latent-arg-traps; see git log): a clipmap
# splice's emit/build boxes are passed explicitly (mesh_clipmap_splice), never inferred from their values,
# and a box with no extent is refused rather than silently read as "no box". Real terrain field (EditStore,
# the collision cook's source), baked the way DcCollisionManager bakes it.
# These pin the fixed contract; they are not old-vs-new reproductions. The box API was renamed, so the old
# binary fails them on the missing method. The old silent full build is shown by scripts/dev/probe_dc_arg_traps.gd.

const ROOT_ORIGIN := Vector3(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0
const SIZE        := 32
const DIM         := SIZE + 1
const DEPTH       := 5
const CENTER      := Vector3(16, 16, 16)
const CAM         := Vector3(16, 16, 120)
const FAR_CAM     := Vector3(16, 16, 5000)
const PROJ        := 500.0
const EPS         := 2.0

var _grid: PackedFloat32Array


func before_all() -> void:
    var s := EditStore.new()
    s.setup(ROOT_ORIGIN, ROOT_SIZE, 30.0, 140.0, 1000.0, 2, 1337)
    var origin := Vector3i(-16, int(round(_surface_y(s))) - 16, -16)
    _grid = s.fill_region(origin, DIM, 1.0, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO)


func _surface_y(s: EditStore) -> float:
    var lo := -400.0
    var hi := 400.0
    for _i in 48:
        var mid := (lo + hi) * 0.5
        if s.sample(Vector3(0.5, mid, 0.5)) < 0.0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) * 0.5


func _full_build(m: DCOctreeMesher) -> Array:
    return m.mesh_clipmap([_grid], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        CENTER, 1e9, DEPTH, CAM, PROJ, EPS, true)


func _splice(m: DCOctreeMesher, emit_min: Vector3i, emit_max: Vector3i, build_min: Vector3i, build_max: Vector3i) -> Array:
    return m.mesh_clipmap_splice([_grid], DIM, PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
        CENTER, 1e9, DEPTH, CAM, PROJ, EPS, true, Vector3i.ZERO, [], PackedColorArray(), false, 0.0,
        emit_min, emit_max, build_min, build_max)


func _indices(arrays: Array) -> PackedInt32Array:
    return PackedInt32Array() if arrays.is_empty() else arrays[Mesh.ARRAY_INDEX]


# The old value test read emit == build == (5,5,5) as "no box": a full build, retained (clobbering the
# real full build), with the box ignored. A zero-extent splice box is refused and the retained build stands.
func test_splice_refuses_zero_extent_box_and_keeps_retained_build() -> void:
    var m := DCOctreeMesher.new()
    assert_false(_full_build(m).is_empty(), "the region has surface (test isn't vacuous)")
    var before := _indices(m.remesh(FAR_CAM, PROJ, EPS))

    var box := Vector3i(5, 5, 5)
    assert_true(_splice(m, box, box, box, box).is_empty(), "a zero-extent splice is refused")
    assert_engine_error("emit box (5, 5, 5)..(5, 5, 5) has no extent", "refused loudly, naming the box")

    assert_eq(_indices(m.remesh(FAR_CAM, PROJ, EPS)), before, "the retained full build is untouched")


# A box flat on one axis (min != max, so the old test took it as a box) holds no cells: refused too.
func test_splice_refuses_flat_or_inverted_box() -> void:
    var m := DCOctreeMesher.new()
    var whole_min := Vector3i.ZERO
    var whole_max := Vector3i(SIZE, SIZE, SIZE)

    assert_true(_splice(m, Vector3i(8, 0, 0), Vector3i(8, SIZE, SIZE), whole_min, whole_max).is_empty(),
        "an emit box flat in x is refused")
    assert_true(_splice(m, whole_min, whole_max, Vector3i(20, 0, 0), Vector3i(10, SIZE, SIZE)).is_empty(),
        "a build box inverted in x is refused")
    assert_engine_error("emit box (8, 0, 0)..(8, 32, 32) has no extent", "the flat emit box is named")
    assert_engine_error("build box (20, 0, 0)..(10, 32, 32) has no extent", "the inverted build box is named")


# A valid splice builds transiently: the retained full build (remesh's source) survives it.
func test_valid_splice_keeps_retained_build() -> void:
    var m := DCOctreeMesher.new()
    _full_build(m)
    var before := _indices(m.remesh(FAR_CAM, PROJ, EPS))

    var core_min := Vector3i(8, 8, 8)
    var core_max := Vector3i(24, 24, 24)
    var apron    := Vector3i.ONE * 4
    assert_false(_splice(m, core_min, core_max, core_min - apron, core_max + apron).is_empty(), "the splice meshed its core")

    assert_eq(_indices(m.remesh(FAR_CAM, PROJ, EPS)), before, "the retained full build is untouched")
