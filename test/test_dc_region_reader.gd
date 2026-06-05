extends GutTest

# Reproduce the "read returned 0" bug headlessly. DCRegionReader.read_sdf_lod0
# should return size^3 values (copy() fills unloaded cells from the generator/
# defaults), regardless of streaming. If it returns 0, the C++ guard that fired
# prints via ERR_PRINT.

func test_reader_returns_region_values() -> void:
    var t := VoxelLodTerrain.new()
    add_child_autofree(t)
    var data := DCRegionReader.new().read_sdf_lod0(t, Vector3i(-4, -4, -4), Vector3i(9, 9, 9))
    gut.p("reader returned %d values (expected 729)" % data.size())
    assert_eq(data.size(), 729, "read_sdf_lod0 must return size^3 values")

# Timing isolation: no generator -> copy() does no noise generation, so any time
# here is the read path itself (copy + the per-voxel get_voxel_f loop).
func test_reader_timing_33_cubed() -> void:
    var t := VoxelLodTerrain.new()
    add_child_autofree(t)
    var n := 33
    var t0 := Time.get_ticks_usec()
    var data := DCRegionReader.new().read_sdf_lod0(t, Vector3i.ZERO, Vector3i(n, n, n))
    var us := Time.get_ticks_usec() - t0
    gut.p("read %d^3 = %d values in %.1f ms (no generator)" % [n, data.size(), us / 1000.0])
    assert_eq(data.size(), n * n * n)
