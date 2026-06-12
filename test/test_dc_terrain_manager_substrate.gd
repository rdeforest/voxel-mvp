extends GutTest

# Guards the DCTerrainManager full-build path (dispatch -> worker -> finish) across the sub-metre
# parameterization. Assertions are in WORLD coordinates (verts through the mesh instance's
# transform), so they hold at any RENDER_BASE_CELL: the rendered terrain must sit around the focus,
# on the terrain surface, regardless of the internal lattice/base-cell scaling. This is the
# behaviour-preserving guard for Stage 0 and the correctness guard for the Stage 1 flip to 0.25.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

func _store() -> EditStore:
    var es := EditStore.new()
    es.setup(Vector3(-512, -512, -512), 1024.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return es

func _surface(x: float, z: float) -> float:
    return SparseVoxelOctree.terrain_surface(x, z, BASE, AMP, PERIOD, OCTAVES, SEED)


func test_full_build_renders_terrain_in_world_space() -> void:
    var focus := Vector3(0, _surface(0, 0), 0)
    var mgr := DCTerrainManager.new()
    add_child_autofree(mgr)
    var follow := Node3D.new()
    add_child_autofree(follow)
    follow.global_position = focus
    mgr.setup(follow, _store())
    mgr._enabled = true
    mgr.error_driven = false   # no Camera3D in the headless test → proj=0 would collapse everything;
                               # uniform build is camera-independent and exercises the same geometry path

    mgr._dispatch(focus)
    mgr._finish()   # blocks on the worker, installs the mesh + cache

    var arrays: Array = mgr._cache_arrays
    assert_false(arrays.is_empty(), "full build produced a cached mesh")
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    assert_gt(verts.size(), 500, "meaningfully tessellated terrain")

    # World transform of the rendered mesh (verts are lattice/base-cell; the instance transform
    # scales + positions them into world). Sample the surface height under the focus and assert the
    # rendered verts near the focus column hug it — proves the world scale/origin are correct.
    var xform := mgr._mesh_instance.global_transform
    var near := 0
    var hugged := 0
    for v in verts:
        var w := xform * v
        if absf(w.x - focus.x) < 6.0 and absf(w.z - focus.z) < 6.0:
            near += 1
            if absf(w.y - _surface(w.x, w.z)) < 4.0:
                hugged += 1
    assert_gt(near, 20, "rendered verts exist in the focus column (correct world position)")
    assert_gt(float(hugged) / float(maxi(near, 1)), 0.8, "those verts hug the terrain surface (correct world scale)")
