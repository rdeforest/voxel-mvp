extends GutTest

# EditStore.sample / fill_region cost on the predict store (edited leaves at 2 m .. 0.25 m beside the
# generator), for edit-store-subdivide-float32-neighbours: an edited leaf now reads its field through
# the node it links (itself or its FIELD_SOURCE). fill_region is the C++ loop the collision buffer
# runs (no GDScript per point). Run: bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/dev/bench_store_sample.gd

const PredictStore := preload("res://test/support/predict_store.gd")
const REPS := 9


func test_bench() -> void:
    var fixture := PredictStore.new()
    var store   := fixture.store
    var origin  := Vector3i(fixture.base) - Vector3i.ONE * 16
    var times: Array[float] = []
    for r in REPS:
        var t0 := Time.get_ticks_usec()
        store.fill_region(origin * 4, 128, 0.25, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO)
        times.append((Time.get_ticks_usec() - t0) / 1000.0)
    times.sort()
    gut.p("fill_region 128^3 @0.25 m over the edits: median %.2f ms (min %.2f)" % [times[REPS / 2], times[0]])
    var inner := (Vector3i(fixture.base) - Vector3i.ONE * 4) * 8
    times.clear()
    for r in REPS:
        var t0 := Time.get_ticks_usec()
        store.fill_region(inner, 64, 0.125, PackedFloat32Array(), Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO)
        times.append((Time.get_ticks_usec() - t0) / 1000.0)
    times.sort()
    gut.p("fill_region 64^3 @0.125 m inside the edits: median %.2f ms (min %.2f)" % [times[REPS / 2], times[0]])
    pass_test("bench")
