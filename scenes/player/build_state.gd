class_name BuildState
extends RefCounted

signal changed()

var _parts: Array[Part] = [
    preload("res://assets/parts/beam/beam.tres"),
    preload("res://assets/parts/slab/slab.tres"),
    preload("res://assets/parts/log/log.tres"),   # 0.5m sub-metre log (resolves at the 0.25 grid)
]
var _materials:    Array[StringName] = [&"Wood", &"Stone", &"Metal", &"Dirt", &"Sand"]
var _build_meshes: Array[BoxMesh]    = []

var _part_index:     int      = 0
var _material_index: int      = 0
var rotation:        Vector3  = Vector3.ZERO   # per-axis degrees (continuous; R/T/Y step by ROTATION_STEP)
var placement_offset: Vector3 = Vector3.ZERO   # accumulated by wheel chords; resets on placement / mode change

const ROTATION_STEP := 15.0   # degrees per R/T/Y press — fine enough for ramps/angled trusses


func _init() -> void:
    for p in _parts:
        var box := BoxMesh.new()
        box.size = p.dimensions
        _build_meshes.append(box)


# --- Queries ---

func current_part()     -> Part:       return _parts[_part_index]
func current_material() -> StringName: return _materials[_material_index]
func current_mesh()     -> BoxMesh:    return _build_meshes[_part_index]
func part_name()        -> String:     return _parts[_part_index].resource_path.get_file().get_basename()

func rotation_basis() -> Basis: return VoxelUtils.euler_basis(rotation)


# --- Mutations ---

func prev_part() -> void:
    _part_index = (_part_index - 1 + _parts.size()) % _parts.size()
    changed.emit()

func next_part() -> void:
    _part_index = (_part_index + 1) % _parts.size()
    changed.emit()

func cycle_material() -> void:
    _material_index = (_material_index + 1) % _materials.size()
    changed.emit()

func rotate_y() -> void:
    rotation.y = fposmod(rotation.y + ROTATION_STEP, 360.0)
    changed.emit()

func rotate_x() -> void:
    rotation.x = fposmod(rotation.x + ROTATION_STEP, 360.0)
    changed.emit()

func rotate_z() -> void:
    rotation.z = fposmod(rotation.z + ROTATION_STEP, 360.0)
    changed.emit()

func adjust_offset(delta: Vector3) -> void:
    placement_offset += delta

func reset_offset() -> void:
    placement_offset = Vector3.ZERO

func restore(part_path: String, material: StringName, rot) -> void:
    for i in _parts.size():
        if _parts[i].resource_path == part_path:
            _part_index = i
            break
    for i in _materials.size():
        if _materials[i] == material:
            _material_index = i
            break
    # `rot` is Vector3 (degrees) in current saves; pre-rotation-rework saves stored
    # a Vector3i of quarter-turns. Coerce either to the current Vector3 degrees.
    rotation = Vector3(rot.x, rot.y, rot.z)
    if rot is Vector3i:
        rotation *= 90.0
    changed.emit()
