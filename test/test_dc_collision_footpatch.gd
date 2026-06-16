extends GutTest

# DCCollisionManager foot patch at sub-metre. The cook now works in COLLISION_CELL units and scales
# the shape to world — a scaling/origin bug would put the collision surface at the wrong height
# (player falls through or floats). Assert the cooked faces under the body hug the terrain surface
# in WORLD space.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

func _store() -> EditStore:
    var es := EditStore.new()
    es.setup(Vector3(-256, -256, -256), 512.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return es

func _surface(x: float, z: float) -> float:
    return EditStore.terrain_surface(x, z, BASE, AMP, PERIOD, OCTAVES, SEED)


func test_foot_patch_collision_hugs_the_surface_in_world() -> void:
    var es := _store()
    var s0 := _surface(0, 0)
    var mgr := DCCollisionManager.new()
    add_child_autofree(mgr)
    var player := CharacterBody3D.new()
    add_child_autofree(player)
    player.global_position = Vector3(0, s0, 0)
    mgr.setup(es, player)

    mgr._cook_region(player, DCCollisionManager.PLAYER_REGION)
    var rec: Dictionary = mgr._regions[player]
    var shape: CollisionShape3D = rec["shape"]
    assert_not_null(shape, "the foot patch cooked a collision shape")
    var faces: PackedVector3Array = (shape.shape as ConcavePolygonShape3D).get_faces()
    assert_gt(faces.size(), 0, "the patch has collision triangles")

    # World position of each face vert = the shape's transform applied. Verts near the body column
    # must hug the terrain surface (correct world scale + origin); a cell-scaling bug throws this off.
    var xform := shape.global_transform
    var near := 0
    var hugged := 0
    for v in faces:
        var w := xform * v
        if absf(w.x) < 2.0 and absf(w.z) < 2.0:
            near += 1
            if absf(w.y - _surface(w.x, w.z)) < 1.0:
                hugged += 1
    assert_gt(near, 5, "collision triangles exist under the body (correct world position)")
    assert_gt(float(hugged) / float(maxi(near, 1)), 0.8, "they hug the terrain surface (correct world scale)")
