class_name CsgState
extends RefCounted

# Editing state for the CSG primitive tool: the active shape, material, rotation,
# combine op (add / subtract), and which axis the resize wheel currently grows.
# Mirrors BuildState's role for the Construction tool.
#
# Per-shape behaviour (dimensions, preview mesh, bounds, resize axes, SDF) lives in
# the CsgShape strategy objects. CsgState holds one instance per shape — switching
# shapes doesn't clobber the others' dimensions — and delegates to the active one.

signal changed()

enum Op { ADD, SUBTRACT }

const RESIZE_STEP   := 1.0    # metres per wheel tick — integer sizes mesh cleanly on the 1 m grid
const MIN_DIM       := CsgShape.MIN_DIM
const ROTATION_STEP := 15.0

var shape:       int     = CsgSdf.Shape.BOX
var op:          int     = Op.ADD
var rotation:    Vector3 = Vector3.ZERO   # per-axis degrees (R/T/Y step by ROTATION_STEP)
var active_axis: int     = 0              # which of the active shape's axes the resize wheel grows

var _shapes: Dictionary = {
    CsgSdf.Shape.BOX:      CsgBoxShape.new(),
    CsgSdf.Shape.CYLINDER: CsgCylinderShape.new(),
    CsgSdf.Shape.SPHERE:   CsgSphereShape.new(),
}
var _active: CsgShape = _shapes[CsgSdf.Shape.BOX]

var _materials:      Array[StringName] = MaterialPalette.selectable()
var _material_index: int               = 0


# --- Queries (per-shape behaviour delegates to the active shape) ---

func active_shape() -> CsgShape: return _active

func current_material() -> StringName: return _materials[_material_index]

# Palette id written to the voxel's CHANNEL_INDICES (0 = natural, never used here).
func material_index() -> int: return MaterialPalette.index_of(current_material())

func rotation_basis() -> Basis:
    var b := Basis.IDENTITY
    b = b.rotated(Vector3.RIGHT,   deg_to_rad(rotation.x))
    b = b.rotated(Vector3.UP,      deg_to_rad(rotation.y))
    b = b.rotated(Vector3.FORWARD, deg_to_rad(rotation.z))
    return b

func current_mesh() -> Mesh:       return _active.mesh()
func bounding_extent() -> float:   return _active.bounding_extent()
func axis_dir() -> Vector3:        return _active.axis_dir(active_axis)
func resize_label() -> String:     return _active.resize_label()
func active_axis_label() -> String: return _active.axis_label(active_axis)
func op_label() -> String:         return "ADD" if op == Op.ADD else "SUBTRACT"


# --- Mutations ---

func set_shape(s: int) -> void:
    if shape == s:
        return
    shape  = s
    _active = _shapes[s]
    active_axis = mini(active_axis, _active.axis_count() - 1)
    changed.emit()

func grow(delta: float) -> void:
    _active.grow(active_axis, delta * RESIZE_STEP)
    changed.emit()

func cycle_axis() -> void:
    active_axis = (active_axis + 1) % _active.axis_count()
    changed.emit()

func toggle_op() -> void:
    op = Op.SUBTRACT if op == Op.ADD else Op.ADD
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
