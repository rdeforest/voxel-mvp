extends GutTest

# MmapArena (engine/voxel_dc/dc_mmap_arena.h) backs the octree's cell arenas with a
# mapped temp file, trying $DC_ARENA_DIR, ./tmp, /var/tmp in turn and falling back to
# anonymous memory only when none yields one. DC_ARENA_FAIL_DISK_MMAP refuses the
# mapping in one dir or in all ("*"), which is otherwise impossible to induce on
# demand; the old code hard-crashed there instead of falling back.
#
# is_arena_disk_backed() reads g_arena_anon_fallback, which is process-wide and
# sticky, so the stages run in one test in the only order that keeps each assert
# meaningful: disk-backed control, one dir refused, every dir refused.
#
# Precondition: ./tmp or /var/tmp is on a real (non-tmpfs) disk.

const FAIL_ENV   := "DC_ARENA_FAIL_DISK_MMAP"
const DIR_ENV    := "DC_ARENA_DIR"
const REFUSED    := "user://dc_arena_refused"
const FD_DIR     := "/proc/self/fd"
const CENTER     := Vector3(16, 16, 16)
const RADIUS     := 10.0
const DEPTH      := 5
const DIM        := 33
const CALLS      := 3


func after_each() -> void:
    OS.unset_environment(FAIL_ENV)
    OS.unset_environment(DIR_ENV)


func _sphere_level() -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                data[i] = Vector3(x, y, z).distance_to(CENTER) - RADIUS
                i += 1

    return data


func _mesh(mesher: DCOctreeMesher, level: PackedFloat32Array) -> Array:
    return mesher.mesh_clipmap([level], DIM, PackedVector3Array([Vector3.ZERO]),
            PackedFloat32Array([1.0]), CENTER, 16.0, DEPTH)


func _open_fds() -> int:
    return DirAccess.get_files_at(FD_DIR).size()


func _refuse_first_dir(level: PackedFloat32Array) -> void:
    var refused := ProjectSettings.globalize_path(REFUSED)
    DirAccess.make_dir_recursive_absolute(refused)
    OS.set_environment(DIR_ENV, refused)
    OS.set_environment(FAIL_ENV, refused)
    var mesher := DCOctreeMesher.new()
    _mesh(mesher, level)
    assert_true(mesher.is_arena_disk_backed(),
            "a refused mapping in $DC_ARENA_DIR moves on to the next disk dir, not to RAM")
    OS.unset_environment(DIR_ENV)


func _refuse_every_dir(level: PackedFloat32Array) -> Array:
    OS.set_environment(FAIL_ENV, "*")
    var forced := DCOctreeMesher.new()
    var fds_before := _open_fds()
    var anon_arrays := []
    for call in CALLS:
        anon_arrays = _mesh(forced, level)

    assert_false(forced.is_arena_disk_backed(),
            "every disk mmap refused, so the process-wide anon-fallback flag is set")
    if DirAccess.dir_exists_absolute(FD_DIR):
        assert_eq(_open_fds(), fds_before, "a refused disk mapping closes its temp-file fd")
    else:
        pending("fd-leak check needs %s (Linux only)" % FD_DIR)

    return anon_arrays


func test_disk_mmap_failure_falls_back_in_order() -> void:
    var level := _sphere_level()
    var control := DCOctreeMesher.new()
    var disk_arrays := _mesh(control, level)
    assert_true(control.is_arena_disk_backed(),
            "control: some non-tmpfs temp dir gives a disk-backed arena")

    _refuse_first_dir(level)
    var anon_arrays := _refuse_every_dir(level)

    assert_false(anon_arrays.is_empty(), "the anonymous arena still meshes")
    assert_eq(anon_arrays[Mesh.ARRAY_VERTEX], disk_arrays[Mesh.ARRAY_VERTEX],
            "arena backing does not change the mesh")
    assert_eq(anon_arrays[Mesh.ARRAY_INDEX], disk_arrays[Mesh.ARRAY_INDEX],
            "arena backing does not change the topology")
