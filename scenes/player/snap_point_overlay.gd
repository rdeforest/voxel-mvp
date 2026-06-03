extends Node3D

# Draws every placed part's snap points as small 3-axis "jacks" in world space.
# When the Assembly tool is active and the cursor is on a part, the point
# nearest the cursor (the remove target) is highlighted so removal is legible.
#
# Same ImmediateMesh pattern as voxel_preview_renderer / voxel_grid_overlay.
# Vertices are emitted in world coordinates; this node sits at identity.

const ARM       := 0.12
const COLOR     := Color(0.20, 0.85, 1.0)    # cyan — a snap point
const COLOR_HOT := Color(1.0,  0.85, 0.20)   # yellow — the remove target
const HOT_SCALE := 1.6

var player: CharacterBody3D   # set by player._ready()

var _im: ImmediateMesh


func _ready() -> void:
    _im = ImmediateMesh.new()
    var mi := MeshInstance3D.new()
    mi.mesh              = _im
    mi.material_override = _make_material()
    add_child(mi)

func _process(_delta: float) -> void:
    _im.clear_surfaces()
    if player == null:
        return
    if player.integrity == null:
        return
    var registry: Dictionary = player.integrity.part_support.part_registry
    if registry.is_empty():
        return

    var hot = _hot_point()
    _im.surface_begin(Mesh.PRIMITIVE_LINES)
    for node in registry:
        var proto: Array = registry[node].part.snap_points
        for wp in SnapPoints.world_points(node, proto):
            var is_hot: bool = hot != null and wp.distance_squared_to(hot) < 0.0001
            _emit_jack(wp, COLOR_HOT if is_hot else COLOR, HOT_SCALE if is_hot else 1.0)
    _im.surface_end()


# World position of the snap point the Remove activity would delete, or null.
func _hot_point() -> Variant:
    if player.current_tool().name != "Assembly":
        return null
    var rc: RayCast3D = player.raycast
    if not rc.is_colliding():
        return null
    var collider := rc.get_collider()
    if collider == null or not player.integrity.has_part(collider):
        return null
    var data: PartData = player.integrity.get_part_data(collider)
    return SnapPoints.nearest_world(collider, rc.get_collision_point(), SnapPoints.PICK_RADIUS, data.part.snap_points)

func _emit_jack(p: Vector3, color: Color, arm_scale: float) -> void:
    var a := ARM * arm_scale
    _im.surface_set_color(color)
    _seg(p - Vector3(a, 0, 0), p + Vector3(a, 0, 0))
    _seg(p - Vector3(0, a, 0), p + Vector3(0, a, 0))
    _seg(p - Vector3(0, 0, a), p + Vector3(0, 0, a))

func _seg(a: Vector3, b: Vector3) -> void:
    _im.surface_add_vertex(a)
    _im.surface_add_vertex(b)

static func _make_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.vertex_color_use_as_albedo = true
    mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
    mat.no_depth_test              = true   # snap points stay visible through parts
    return mat
