extends MeshInstance3D

# Fullscreen post-process quad for the line-and-wash ink + vignette. Added under the camera. The
# shader's POSITION override makes it cover the screen regardless of this node's transform; we only
# need it un-cullable (huge custom AABB) and rendering after the terrain (the material reads the
# screen texture, so it lands in the transparent pass; render_priority 100 keeps it last).

const MAT_PATH := "res://assets/materials/watercolor_post.tres"


func _ready() -> void:
    var quad := QuadMesh.new()
    quad.size = Vector2(2, 2)
    mesh = quad
    material_override = load(MAT_PATH)
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # Never frustum-cull the fullscreen quad (its real coverage comes from the POSITION override).
    custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
