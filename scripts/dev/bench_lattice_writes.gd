extends GutTest

# sdf-lattice-writes-false-change-at-max-faces: the cost of settling SdfLattice.writes. A preview
# whose lattice changes some point it reads pays nothing extra; one that looks unchanged runs
# EditStore.lattice_writes, the dry run of the write. Timed per CSG preview (radius-3 sphere, game
# store, real surface) for a real stamp, an identical re-stamp in air (stored leaves) and a union
# buried in deep ground (unedited generator leaves: the dry run's most expensive case).
# Run: bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/dev/bench_lattice_writes.gd
# (Drafted by Claude, overnight 2026-09-26.)

const RADIUS := 3.0
const REPS   := 300


func test_bench() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    var store   := manager.store
    var surface := EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    var ctx   := ActionContext.new(store, null, null)
    var shape := CsgSphereShape.new(RADIUS)
    var at_surface := Transform3D(Basis(), Vector3(100.0, surface, 100.0))
    var in_air     := Transform3D(Basis(), Vector3(100.0, floorf(surface) + 40.0, 100.0))
    var buried     := Transform3D(Basis(), Vector3(100.0, surface - 40.0, 100.0))
    _time_preview("real stamp before any edit", shape, at_surface, ctx)
    CsgAction.new(shape, in_air, CsgState.Op.ADD, &"Stone", ctx).execute()
    for row: Array in [["real stamp at the surface", at_surface], ["re-stamp in air", in_air],
            ["union buried in ground", buried]]:
        var xform: Transform3D = row[1]
        var refused := CsgAction.new(shape, xform, CsgState.Op.ADD, &"Stone", ctx).preview().refused
        var t0 := Time.get_ticks_usec()
        for i in REPS:
            CsgAction.new(shape, xform, CsgState.Op.ADD, &"Stone", ctx).preview()
        var ms  := float(Time.get_ticks_usec() - t0) / 1000.0 / REPS
        var lat := VoxelImprint.lattice(store, shape, xform, CsgState.Op.ADD)
        t0 = Time.get_ticks_usec()
        for i in REPS:
            store.lattice_writes(lat.sdf, lat.dim, lat.origin, lat.cell)
        var dry := float(Time.get_ticks_usec() - t0) / 1000.0 / REPS
        print("%-28s %.3f ms/preview  refused=%s  (full dry run alone %.3f ms)" % [row[0], ms, refused, dry])
    pass_test("timings printed")


func _time_preview(label: String, shape: CsgShape, xform: Transform3D, ctx: ActionContext) -> void:
    var t0 := Time.get_ticks_usec()
    for i in REPS:
        CsgAction.new(shape, xform, CsgState.Op.ADD, &"Stone", ctx).preview()
    print("%-28s %.3f ms/preview" % [label, float(Time.get_ticks_usec() - t0) / 1000.0 / REPS])
