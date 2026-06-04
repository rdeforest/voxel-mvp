extends GutTest

# Regression: terrain SDF edits weren't reaching disk. godot_voxel writes a
# modified block to its VoxelStream only when the block streams out, and it does
# NOT save on exit (NOTIFICATION_EXIT_TREE is a no-op) -- so edits in blocks still
# loaded around the player were lost on reload. The fix is TerrainPersistence.flush()
# (call save_modified_blocks), wired into save (F5) and quit.
#
# The full on-disk round-trip needs a live streaming viewer/engine that GUT can't
# drive headless ("Central buffer must be valid" -- blocks never load), so this
# guards the fix's logic instead: flush MUST call save_modified_blocks when a
# stream is present, and MUST NOT when there isn't (e.g. after `reset` detaches it).

# Stub standing in for a VoxelLodTerrain: a `stream` property and a spied
# save_modified_blocks. flush() is duck-typed, so this exercises its real logic.
class _SpyTerrain:
    extends RefCounted
    var stream = null
    var save_calls := 0
    func save_modified_blocks() -> void:
        save_calls += 1


func test_flush_saves_modified_blocks_when_stream_present() -> void:
    var t := _SpyTerrain.new()
    t.stream = VoxelStreamSQLite.new()
    TerrainPersistence.flush(t)
    assert_eq(t.save_calls, 1, "flush must save modified blocks when a stream is set")

func test_flush_skips_when_no_stream() -> void:
    var t := _SpyTerrain.new()
    t.stream = null
    TerrainPersistence.flush(t)
    assert_eq(t.save_calls, 0, "flush must not save when there is no stream (e.g. after reset)")

func test_flush_null_terrain_is_safe() -> void:
    TerrainPersistence.flush(null)
    assert_true(true, "flush(null) must not crash")
