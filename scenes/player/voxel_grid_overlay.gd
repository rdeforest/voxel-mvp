extends MeshInstance3D

# Debug overlay: wireframes the targeted voxel and its neighbourhood,
# fading by Chebyshev shell distance. Helps the player understand
# where voxel boundaries fall when predicting flatten / dig / fill.

const SHELL_ALPHAS := [0.9, 0.6, 0.3, 0.1]   # shell 0 = targeted cell
const GREY         := Color(0.85, 0.85, 0.85)

var raycast: RayCast3D       # assigned by player._ready
var enabled: bool    = false
var _im:     ImmediateMesh


func _ready() -> void:
    _im = ImmediateMesh.new()
    mesh = _im
    material_override = OverlayMaterial.make(false)
    visible = false

func toggle() -> void:
    enabled = not enabled
    visible = enabled
    if not enabled:
        _im.clear_surfaces()

func _process(_delta: float) -> void:
    if not enabled or raycast == null:
        return
    if not raycast.is_colliding():
        _im.clear_surfaces()
        return
    var hit := raycast.get_collision_point()
    var normal := raycast.get_collision_normal()
    # Step slightly into the hit surface so we pick the solid cell,
    # not the air cell on the player's side.
    var inside := hit - normal * VoxelConstants.SURFACE_NUDGE
    var center := Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
    _redraw(center)


func _redraw(center: Vector3i) -> void:
    _im.clear_surfaces()
    _im.surface_begin(Mesh.PRIMITIVE_LINES)
    for shell in SHELL_ALPHAS.size():
        var color := GREY
        color.a    = SHELL_ALPHAS[shell]
        for cell in _shell_cells(center, shell):
            _draw_cube_edges(cell, color)
    _im.surface_end()

func _draw_cube_edges(cell: Vector3i, color: Color) -> void:
    var base := Vector3(cell)
    _im.surface_set_color(color)
    for edge in CubeGeometry.EDGES:
        _im.surface_add_vertex(base + CubeGeometry.corner(edge[0]))
        _im.surface_add_vertex(base + CubeGeometry.corner(edge[1]))

static func _shell_cells(center: Vector3i, d: int) -> Array[Vector3i]:
    if d == 0:
        return [center]
    var out: Array[Vector3i] = []
    for dx in range(-d, d + 1):
        for dy in range(-d, d + 1):
            for dz in range(-d, d + 1):
                if max(absi(dx), max(absi(dy), absi(dz))) == d:
                    out.append(center + Vector3i(dx, dy, dz))
    return out
