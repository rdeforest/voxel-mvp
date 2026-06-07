class_name CsgState
extends RefCounted

# Editing state for the CSG primitive tool: the active shape, its dimensions,
# material, rotation, combine op (add / subtract), and which axis the resize
# wheel currently grows. Mirrors BuildState's role for the Construction tool.
#
# Dimensions are kept per shape (a box has three independent extents; a cylinder
# has radius + height; a sphere has one radius) so switching shapes doesn't
# clobber the others. `dims()` packs the active shape's parameters into the
# Vector3 that CsgSdf consumes.

signal changed()

enum Op { ADD, SUBTRACT }

const RESIZE_STEP := 1.0   # metres per wheel tick — integer sizes mesh cleanly on the 1 m grid
const MIN_DIM     := 1.0

var shape:       int = CsgSdf.Shape.BOX
var op:          int = Op.ADD
var rotation:    Vector3 = Vector3.ZERO   # per-axis degrees (R/T/Y step by ROTATION_STEP)
var active_axis: int     = 0              # 0=X, 1=Y, 2=Z — the axis the resize wheel grows

var box_size:     Vector3 = Vector3(4.0, 4.0, 4.0)
var cyl_radius:   float   = 2.0
var cyl_height:   float   = 5.0
var sphere_radius:float   = 3.0

const ROTATION_STEP := 15.0

var _materials:     Array[StringName] = MaterialPalette.selectable()
var _material_index:int               = 0


# --- Queries ---

func current_material() -> StringName: return _materials[_material_index]

# Palette id written to the voxel's CHANNEL_INDICES (0 = natural, never used here).
func material_index() -> int: return MaterialPalette.index_of(current_material())

func dims() -> Vector3:
    match shape:
        CsgSdf.Shape.BOX:      return box_size
        CsgSdf.Shape.CYLINDER: return Vector3(cyl_radius, cyl_height, 0.0)
        CsgSdf.Shape.SPHERE:   return Vector3(sphere_radius, 0.0, 0.0)
    return Vector3.ONE

func rotation_basis() -> Basis:
    var b := Basis.IDENTITY
    b = b.rotated(Vector3.RIGHT,   deg_to_rad(rotation.x))
    b = b.rotated(Vector3.UP,      deg_to_rad(rotation.y))
    b = b.rotated(Vector3.FORWARD, deg_to_rad(rotation.z))
    return b

func current_mesh() -> Mesh:
    match shape:
        CsgSdf.Shape.BOX:
            var bm := BoxMesh.new()
            bm.size = box_size
            return bm
        CsgSdf.Shape.CYLINDER:
            var cm := CylinderMesh.new()
            cm.top_radius    = cyl_radius
            cm.bottom_radius = cyl_radius
            cm.height        = cyl_height
            return cm
        CsgSdf.Shape.SPHERE:
            var sm := SphereMesh.new()
            sm.radius = sphere_radius
            sm.height = sphere_radius * 2.0
            return sm
    return null

# Largest world-space dimension of the current shape (for the air-preview distance).
func bounding_extent() -> float:
    match shape:
        CsgSdf.Shape.BOX:      return maxf(box_size.x, maxf(box_size.y, box_size.z))
        CsgSdf.Shape.CYLINDER: return maxf(cyl_radius * 2.0, cyl_height)
        CsgSdf.Shape.SPHERE:   return sphere_radius * 2.0
    return 1.0

# Local-space direction of the axis the resize wheel currently grows, so the
# preview can point an arrow at it. A sphere resizes uniformly (no meaningful
# axis) so it returns ZERO and the arrow hides.
func axis_dir() -> Vector3:
    match shape:
        CsgSdf.Shape.SPHERE:
            return Vector3.ZERO
        CsgSdf.Shape.CYLINDER:
            return Vector3.UP if active_axis == 1 else Vector3.RIGHT
        _:
            return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][active_axis]

func resize_label() -> String:
    match shape:
        CsgSdf.Shape.BOX:      return "X×Y×Z %.0f×%.0f×%.0f" % [box_size.x, box_size.y, box_size.z]
        CsgSdf.Shape.CYLINDER: return "r %.0f  h %.0f" % [cyl_radius, cyl_height]
        CsgSdf.Shape.SPHERE:   return "r %.0f" % sphere_radius
    return ""

func active_axis_label() -> String:
    if shape == CsgSdf.Shape.SPHERE:
        return "radius"
    if shape == CsgSdf.Shape.CYLINDER:
        return "height" if active_axis == 1 else "radius"
    return ["X", "Y", "Z"][active_axis]

func op_label() -> String:
    return "ADD" if op == Op.ADD else "SUBTRACT"


# --- Mutations ---

func set_shape(s: int) -> void:
    if shape == s:
        return
    shape = s
    changed.emit()

func grow(delta: float) -> void:
    var step := delta * RESIZE_STEP
    match shape:
        CsgSdf.Shape.BOX:
            box_size[active_axis] = maxf(MIN_DIM, box_size[active_axis] + step)
        CsgSdf.Shape.CYLINDER:
            if active_axis == 1:
                cyl_height = maxf(MIN_DIM, cyl_height + step)
            else:
                cyl_radius = maxf(MIN_DIM, cyl_radius + step)
        CsgSdf.Shape.SPHERE:
            sphere_radius = maxf(MIN_DIM, sphere_radius + step)
    changed.emit()

func cycle_axis() -> void:
    active_axis = (active_axis + 1) % 3
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
