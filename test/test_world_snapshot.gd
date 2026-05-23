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
        "parts": [
            {
                "part_path":   "res://assets/parts/beam/beam.tres",
                "material":    "Wood",
                "placement_y": 4.0,
                "transform":   Transform3D.IDENTITY,
                "cells":       [Vector3i(0, 0, 0), Vector3i(1, 0, 0)] as Array[Vector3i],
            },
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
        assert_eq(deserialized["parts"][0]["transform"],     Transform3D.IDENTITY)
        assert_eq(deserialized["parts"][0]["cells"][1],      Vector3i(1, 0, 0))

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
        "parts":   [],
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
