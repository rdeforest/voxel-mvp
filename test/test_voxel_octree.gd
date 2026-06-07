extends GutTest

# The substrate's storage thesis: a sparse adaptive octree can store an edited SDF at
# SUB-METRE resolution, reconstruct it accurately, and use storage that scales with
# surface AREA (not volume) — store the skin, not the rock.

const ROOT := 16.0
const CENTER := Vector3(8, 8, 8)
const RADIUS := 5.0
const MIN_LEAF := 0.25     # sub-metre — finer than godot_voxel's 1 m grid


func _sphere(p: Vector3) -> float:
    return p.distance_to(CENTER) - RADIUS


func _imprinted() -> VoxelOctree:
    var t := VoxelOctree.new(Vector3.ZERO, ROOT)
    t.imprint(_sphere, MIN_LEAF, 3)
    return t


func test_reconstructs_surface_sub_metre() -> void:
    var t := _imprinted()
    # March along +X from the centre; the stored field must cross zero within a
    # sub-metre band of the true radius (5.0).
    var crossing := 0.0
    for i in range(1, 800):
        var x := i * 0.02
        if t.sample(CENTER + Vector3(x, 0, 0)) >= 0.0:
            crossing = x
            break
    gut.p("reconstructed radius = %.3f (true %.1f)" % [crossing, RADIUS])
    assert_almost_eq(crossing, RADIUS, MIN_LEAF, "surface reconstructed to sub-metre accuracy")


func test_material_stored() -> void:
    var t := _imprinted()
    assert_eq(t.material_at(CENTER), 3, "leaf material is read back")


func test_inside_is_solid_outside_is_air() -> void:
    var t := _imprinted()
    assert_lt(t.sample(CENTER), 0.0, "deep inside the sphere reads solid (negative)")
    assert_gt(t.sample(Vector3(0.5, 0.5, 0.5)), 0.0, "far outside reads air (positive)")

func test_fresh_tree_is_empty() -> void:
    var t := VoxelOctree.new(Vector3.ZERO, ROOT)
    assert_eq(t.sample(CENTER), VoxelOctree.EMPTY, "nothing imprinted yet -> EMPTY (use the generator)")


func test_storage_tracks_area_not_volume() -> void:
    var t := _imprinted()
    var leaves := t.leaf_count()
    # Dense would be (ROOT/MIN_LEAF)^3 = 64^3 = 262144. Surface-only is ~ (R/leaf)^2 * k,
    # orders of magnitude fewer. Assert it's a small fraction of the dense count.
    var dense := pow(ROOT / MIN_LEAF, 3)
    gut.p("leaves=%d  dense-equivalent=%d  ratio=%.4f" % [leaves, int(dense), leaves / dense])
    assert_lt(leaves, dense * 0.1, "sparse: stores the surface, not the volume")
    assert_gt(leaves, 0, "but it did store the surface")
