extends GutTest

# actions-preview-gdscript-slow: time the preview's lattice + flip prediction per call, GDScript
# (SdfLattice / VoxelImprint / StoreWrite + flips) against EditStore.predict_*, for a radius-3 brush
# on the game's store at a real surface point. Also times each action's whole preview() as it stands.
# Run (GUT, for the autoloads): bin/godot --path . --headless -s addons/gut/gut_cmdln.gd \
#     -gtest=res://scripts/dev/bench_preview_predict.gd

const RADIUS := 3.0
const REPS   := 200


func test_bench() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    var store := manager.store
    var ctx   := ActionContext.new(store, null, null)
    var at    := Vector3(100.0, EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED), 100.0)

    var sub  := VoxelConstants.STORE_OP_SUBTRACT
    var leaf := VoxelConstants.RENDER_BASE_CELL
    _row("dig lattice+flips", _ms(func() -> void: SdfLattice.sphere_stamp(store, at, RADIUS, sub, leaf).flips(store)),
        _ms(func() -> void: store.predict_sphere_stamp(at, RADIUS, sub, leaf)))

    var shape := CsgSphereShape.new(RADIUS)
    var xform := Transform3D(Basis(), at)
    var add   := CsgState.Op.ADD
    _row("CSG sphere lattice+flips", _ms(func() -> void: VoxelImprint.lattice(store, shape, xform, add).flips(store)),
        _ms(func() -> void: store.predict_imprint(CsgSdf.Shape.SPHERE, PackedFloat64Array([RADIUS]), xform, add, leaf)))

    _work_row("raise", RaiseAction.new(at, RADIUS, ctx)._compute_work(), store)
    _work_row("flatten", FlattenAction.new(at, Vector3.UP, RADIUS, ctx)._compute_work(), store)

    _row("raise _compute_work (unchanged by C++)", _ms(func() -> void: RaiseAction.new(at, RADIUS, ctx)._compute_work()), -1.0)
    _row("flatten _compute_work (unchanged by C++)",
        _ms(func() -> void: FlattenAction.new(at, Vector3.UP, RADIUS, ctx)._compute_work()), -1.0)
    _row("dig preview() today", _ms(func() -> void: DigAction.new(at, RADIUS, ctx).preview()), -1.0)

    var player := at + Vector3(4.5, 1.5, 0.0)
    _safety_row("dig", SdfLattice.sphere_stamp(store, at, RADIUS, sub, leaf), store, player)
    _safety_row("CSG sphere", VoxelImprint.lattice(store, shape, xform, add), store, player)
    _safety_row("raise", StoreWrite.lattice(store, RaiseAction.new(at, RADIUS, ctx)._compute_work()), store, player)
    pass_test("timings printed")


func _work_row(label: String, work: Array[LatticeEdit], store: EditStore) -> void:
    var points: Array[Vector3i] = []
    var sdfs := PackedFloat64Array()
    for edit in work:
        points.append(edit.point)
        sdfs.append(edit.sdf)
    _row("%s lattice+flips (%d points)" % [label, work.size()],
        _ms(func() -> void: StoreWrite.lattice(store, work).flips(store)),
        _ms(func() -> void: store.predict_work(points, sdfs)))


# PlayerSafeAction.endangered_by's body, for a player standing at the brush's edge where the
# capsule and support boxes overlap rewritten leaves but nothing flips: the full scan, no early out.
func _safety_row(label: String, lat: SdfLattice, store: EditStore, player: Vector3) -> void:
    var capsule := PlayerSafeAction.capsule_box(player)
    var support := PlayerSafeAction.support_box(player)
    var endangered := lat.solidifies_in(store, capsule) or lat.empties_in(store, support)
    _row("%s endangered_by (GDScript only; hit=%s)" % [label, endangered],
        _ms(func() -> void: lat.solidifies_in(store, capsule) or lat.empties_in(store, support)), -1.0)


func _ms(body: Callable) -> float:
    body.call()
    var start := Time.get_ticks_usec()
    for _i in REPS:
        body.call()
    return float(Time.get_ticks_usec() - start) / 1000.0 / REPS


func _row(label: String, gdscript_ms: float, cpp_ms: float) -> void:
    var cpp := "%.3f ms" % cpp_ms if cpp_ms >= 0.0 else "-"
    print("%-45s GDScript %.3f ms   C++ %s" % [label, gdscript_ms, cpp])
