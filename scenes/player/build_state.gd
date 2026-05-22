class_name BuildState
extends RefCounted

signal changed()

var _parts: Array[Part] = [
    preload("res://assets/parts/board/board.tres"),
    preload("res://assets/parts/plank/plank.tres"),
    preload("res://assets/parts/stud/stud.tres"),
    preload("res://assets/parts/beam/beam.tres"),
]
var _materials:    Array[StringName] = [&"Wood", &"Stone", &"Metal", &"Dirt", &"Sand"]
var _build_meshes: Array[BoxMesh]    = []

var _part_index:     int      = 0
var _material_index: int      = 0
var rotation:        Vector3i = Vector3i.ZERO


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

func rotation_basis() -> Basis:
    var b := Basis.IDENTITY
    b = b.rotated(Vector3.RIGHT,   rotation.x * PI * 0.5)
    b = b.rotated(Vector3.UP,      rotation.y * PI * 0.5)
    b = b.rotated(Vector3.FORWARD, rotation.z * PI * 0.5)
    return b


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
    rotation.y = (rotation.y + 1) % 4
    changed.emit()

func rotate_x() -> void:
    rotation.x = (rotation.x + 1) % 4
    changed.emit()

func rotate_z() -> void:
    rotation.z = (rotation.z + 1) % 4
    changed.emit()
