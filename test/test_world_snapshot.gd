extends GutTest

# WorldSnapshot.refusal() accepts only the current schema: one save format until there are play
# testers. Tests at the file-IO + parse level — the apply() leg needs a real terrain so we don't go
# that far.
class TestSnapshotVersionCompat:
    extends GutTest

    const TMP_PATH := "user://test_version_compat.tmp"

    func after_each():
        DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

    func _write(snap: Dictionary) -> void:
        var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
        file.store_string(var_to_str(snap))

    func test_current_version_is_accepted():
        _write({"version": WorldSnapshot.VERSION, "save_id": 1, "player": var_to_bytes({}),
            "voxels": var_to_bytes([]), "parts": var_to_bytes({"next_id": 1, "records": []})})
        assert_eq(WorldSnapshot.refusal(WorldSnapshot.read(TMP_PATH)), "")

    func test_older_version_rejected():
        for version in [2, WorldSnapshot.VERSION - 1]:
            _write({"version": version, "player": {}, "voxels": [], "parts": []})
            assert_eq(WorldSnapshot.refusal(WorldSnapshot.read(TMP_PATH)),
                "world snapshot is format v%d; this build reads only v%d" % [version, WorldSnapshot.VERSION])

    func test_newer_version_rejected():
        _write({"version": WorldSnapshot.VERSION + 1, "player": {}, "voxels": [], "parts": []})
        assert_string_contains(WorldSnapshot.refusal(WorldSnapshot.read(TMP_PATH)),
            "format v%d" % (WorldSnapshot.VERSION + 1), "newer-than-known version is refused")

    func test_nonexistent_file_returns_false():
        var fake := "user://does_not_exist_%d.tmp" % Time.get_ticks_msec()
        assert_eq(WorldSnapshot.refusal(WorldSnapshot.read(fake)), "world snapshot is unreadable")

    func test_v3_tunables_section_serializes_through_var_to_str():
        # Verifies the V3 shape round-trips. Apply uses get/set_shader_parameter
        # which needs a real material, so we only test the data layer here.
        var snap := {
            "version":  3,
            "player":   {},
            "voxels":   [],
            "parts":    [],
            "tunables": {
                "wave_speed":  1.5,
                "grass_color": Color(0.35, 0.55, 0.22),
                "wave_dir":    Vector2(0.7, 0.3),
            },
        }
        var parsed = str_to_var(var_to_str(snap))
        assert_eq(parsed["tunables"]["wave_speed"],  1.5)
        assert_eq(parsed["tunables"]["grass_color"], Color(0.35, 0.55, 0.22))
        assert_eq(parsed["tunables"]["wave_dir"],    Vector2(0.7, 0.3))

    func test_v4_tool_state_section_serializes():
        var snap := {
            "version": 4,
            "player": {
                "position":         Vector3.ZERO,
                "body_rotation_y":  0.0,
                "head_rotation_x":  0.0,
                "tool_index":       1,
                "activity_indices": [0, 3, 1],
                "build_part_path":  "res://assets/parts/beam/beam.tres",
                "build_material":   "Wood",
                "build_rotation":   Vector3i.ZERO,
            },
            "voxels": [], "parts": [], "tunables": {},
        }
        var parsed = str_to_var(var_to_str(snap))
        assert_eq(parsed["player"]["tool_index"], 1)
        assert_eq(parsed["player"]["activity_indices"][1], 3)
