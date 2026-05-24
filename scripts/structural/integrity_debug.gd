class_name IntegrityDebug
extends RefCounted

const VOXEL_SIZE := 0.3

var enabled:          bool       = true
var _meshes:          Dictionary = {}
var _terrain_support: TerrainSupport
var _container:       Node


func _init(terrain_support: TerrainSupport, container: Node) -> void:
    _terrain_support = terrain_support
    _container       = container


func set_enabled(value: bool) -> void:
    if value == enabled:
        return
    enabled = value
    if not enabled:
        _clear()

func update(pulse: float, straining: Dictionary) -> void:
    if not enabled:
        return

    for pos in _meshes.keys():
        if not _terrain_support.voxel_data.has(pos):
            _meshes[pos].queue_free()
            _meshes.erase(pos)

    for pos in _terrain_support.voxel_data:
        var support: float = _terrain_support.voxel_data[pos].support
        var color          := StructuralIntegrity.get_support_color(support)
        color.a = lerpf(0.15, 0.9, pulse) if straining.has(pos) else 0.6

        if _meshes.has(pos):
            (_meshes[pos].material_override as StandardMaterial3D).albedo_color = color
        else:
            _meshes[pos] = _make_cube(pos, color)


func _make_cube(pos: Vector3i, color: Color) -> MeshInstance3D:
    var box := BoxMesh.new()
    box.size = Vector3.ONE * VOXEL_SIZE

    var mat := StandardMaterial3D.new()
    mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.no_depth_test = true
    mat.albedo_color  = color

    var mi := MeshInstance3D.new()
    mi.mesh              = box
    mi.material_override = mat
    _container.add_child(mi)
    mi.global_position   = Vector3(pos) + Vector3.ONE * 0.5
    return mi

func _clear() -> void:
    for pos in _meshes:
        _meshes[pos].queue_free()
    _meshes.clear()
