extends GutTest

# Where a construction preview's time goes after the attach scan moved to C++: each stage of
# ConstructionAction.preview() timed alone, for the beam resting on the surface and floating 3 m up.
# Run: bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/dev/bench_construction_preview.gd
# (Drafted by Claude, overnight 2026-09-26.)

const REPS := 1000

var _store: EditStore


func test_bench() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    _store = manager.store
    var at := Vector3(100.0, EditStore.terrain_surface(100.0, 100.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED), 100.0)
    var beam := preload("res://assets/parts/beam/beam.tres")
    var ctx  := ActionContext.new(_store, null, null)
    for lift: float in [0.0, 3.0]:
        var pos := at + Vector3.UP * lift
        var build := ConstructionAction.new(beam, pos, Vector3.ZERO, &"Wood", ctx)
        build._ensure_flips()
        var shape := build._shape()
        var xform := build._xform()
        var lat   := build._lattice
        print("--- beam +%.0f m (lattice dim %d, %d points) ---" % [lift, lat.dim, lat.dim * lat.dim * lat.dim])
        _row("preview()", func() -> void: ConstructionAction.new(beam, pos, Vector3.ZERO, &"Wood", ctx).preview())
        _row("new()", func() -> void: ConstructionAction.new(beam, pos, Vector3.ZERO, &"Wood", ctx))
        _row("_shape + _xform", func() -> void:
            build._shape()
            build._xform())
        _row("predict_imprint", func() -> void:
            _store.predict_imprint(shape.sdf_kind(), shape.sdf_dims(), xform, CsgState.Op.ADD, 1.0))
        _row("SdfLattice.predicted", func() -> void:
            VoxelImprint.lattice(_store, shape, xform, CsgState.Op.ADD))
        _row("lattice_flips", func() -> void: lat.flips(_store))
        _row("imprint_near_solid", func() -> void: build._attached())
        _row("_part_cells (uncached)", func() -> void:
            VoxelUtils.footprint_from_aabb(build._xform() * build._shape().local_aabb()))
    pass_test("timings printed")


func _row(label: String, body: Callable) -> void:
    body.call()
    var start := Time.get_ticks_usec()
    for _i in REPS:
        body.call()
    print("%-24s %.4f ms" % [label, float(Time.get_ticks_usec() - start) / 1000.0 / REPS])
