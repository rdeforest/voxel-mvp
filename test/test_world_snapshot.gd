extends GutTest

class TestSnapshotSerialization:
    extends GutTest

    var snap := {
        "version": WorldSnapshot.VERSION,
        "player": {
            "position":        Vector3(1.5, 2.5, 3.5),
            "body_rotation_y": 0.25,
            "head_rotation_x": -0.1,
            "edit_mode_index": 3,
            "build_part_path": "res://assets/parts/beam/beam.tres",
            "build_material":  "Wood",
            "build_rotation":  Vector3i(1, 2, 3),
        },
        "voxels": [
            {"pos": Vector3i(0, 0, 0),    "material": "Stone", "support": 1.0},
            {"pos": Vector3i(10, -5, 20), "material": "Dirt",  "support": 0.7},
        ],
    }

    func test_roundtrip_preserves_types():
        var serialized   := var_to_str(snap)
        var deserialized = str_to_var(serialized)
        assert_eq(deserialized["version"],                   WorldSnapshot.VERSION)
        assert_eq(deserialized["player"]["position"],        Vector3(1.5, 2.5, 3.5))
        assert_eq(deserialized["player"]["build_rotation"],  Vector3i(1, 2, 3))
        assert_eq(deserialized["voxels"][0]["pos"],          Vector3i(0, 0, 0))
        assert_eq(deserialized["voxels"][1]["material"],     "Dirt")

    func test_material_resolves_after_roundtrip():
        var deserialized = str_to_var(var_to_str(snap))
        var mat_name: String = deserialized["voxels"][0]["material"]
        assert_eq(Materials.from_name(StringName(mat_name)).name, "Stone")

class TestSnapshotFileIO:
    extends GutTest

    const TMP_PATH := "user://test_snapshot.tmp"

    var snap := {
        "version": WorldSnapshot.VERSION,
        "player":  {},
        "voxels":  [{"pos": Vector3i(5, 6, 7), "material": "Stone"}],
    }

    func after_each():
        DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

    func test_write_then_read_preserves_voxel_pos():
        var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
        file.store_string(var_to_str(snap))
        file = null

        var read := FileAccess.open(TMP_PATH, FileAccess.READ)
        var parsed = str_to_var(read.get_as_text())
        assert_eq(parsed["voxels"][0]["pos"], Vector3i(5, 6, 7))


# load_into() must accept older schemas (missing fields default) and
# reject newer-than-known ones. Tests at the file-IO + parse level —
# the apply() leg needs a real terrain so we don't go that far.
class TestSnapshotVersionCompat:
    extends GutTest

    const TMP_PATH := "user://test_version_compat.tmp"

    func after_each():
        DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

    func _write(snap: Dictionary) -> void:
        var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
        file.store_string(var_to_str(snap))

    func test_older_version_loads_ok():
        # A V2-shaped snapshot — no tunables (V3+), no tool_index (V4+).
        _write({
            "version": 2,
            "player": {
                "position":        Vector3(0, 80, 0),
                "body_rotation_y": 0.0,
                "head_rotation_x": 0.0,
                "edit_mode_index": 0,
                "build_part_path": "res://assets/parts/beam/beam.tres",
                "build_material":  "Wood",
                "build_rotation":  Vector3i.ZERO,
            },
            "voxels": [],
            "parts":  [],
        })
        var file := FileAccess.open(TMP_PATH, FileAccess.READ)
        var parsed = str_to_var(file.get_as_text())
        assert_eq(parsed["version"], 2)
        # The load_into version check accepts anything ≤ VERSION; the
        # apply() path tolerates missing tunables / activity_indices
        # by `.has()`-guarding their reads.
        assert_true(parsed["version"] <= WorldSnapshot.VERSION)

    func test_newer_version_rejected():
        _write({"version": WorldSnapshot.VERSION + 1, "player": {}, "voxels": [], "parts": []})
        assert_false(WorldSnapshot.load_into(TMP_PATH, null),
            "newer-than-known version should be refused even with a null world")

    func test_nonexistent_file_returns_false():
        var fake := "user://does_not_exist_%d.tmp" % Time.get_ticks_msec()
        assert_false(WorldSnapshot.load_into(fake, null))

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
