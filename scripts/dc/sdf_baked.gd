class_name SdfBaked
extends SdfField

# Field pre-sampled onto a regular grid: reads only (no callable per sample),
# gradients via central differences on the stored data at grid resolution. This
# is the information the engine's stored scalar SDF actually provides, so it
# meshes the same geometry as SdfAnalytic but with softer creases (exact
# crossing normals are lost — the Bite E storage tradeoff). Also useful for
# isolating callable/analytic cost and for A/B troubleshooting.

var _data:   PackedFloat32Array
var _origin: Vector3
var _cell:   float
var _dim:    Vector3i        # samples per axis (corners, not cells)


func _init(data: PackedFloat32Array, origin: Vector3, cell: float, dim: Vector3i) -> void:
    _data   = data
    _origin = origin
    _cell   = cell
    _dim    = dim

# Sample `src` over the lattice [origin, origin + (dim-1)*cell] into a flat array.
static func bake(src: SdfField, origin: Vector3, cell: float, dim: Vector3i) -> SdfBaked:
    var data := PackedFloat32Array()
    data.resize(dim.x * dim.y * dim.z)
    var i := 0
    for z in dim.z:
        for y in dim.y:
            for x in dim.x:
                data[i] = src.value(origin + Vector3(x, y, z) * cell)
                i += 1
    return SdfBaked.new(data, origin, cell, dim)


func value(p: Vector3) -> float:
    return _at(p)                         # exact at lattice points, trilinear between

func gradient(p: Vector3) -> Vector3:
    var h := _cell                        # central difference at grid resolution
    var dx := _at(p + Vector3(h, 0, 0)) - _at(p - Vector3(h, 0, 0))
    var dy := _at(p + Vector3(0, h, 0)) - _at(p - Vector3(0, h, 0))
    var dz := _at(p + Vector3(0, 0, h)) - _at(p - Vector3(0, 0, h))
    var g := Vector3(dx, dy, dz)
    return g.normalized() if g.length_squared() > 0.0 else Vector3.UP


# --- internals ---

func _grid(x: int, y: int, z: int) -> float:
    x = clampi(x, 0, _dim.x - 1)
    y = clampi(y, 0, _dim.y - 1)
    z = clampi(z, 0, _dim.z - 1)
    return _data[x + _dim.x * (y + _dim.y * z)]

func _at(world: Vector3) -> float:
    var l  := (world - _origin) / _cell
    var x0 := floori(l.x)
    var y0 := floori(l.y)
    var z0 := floori(l.z)
    var fx := l.x - x0
    var fy := l.y - y0
    var fz := l.z - z0
    var c00 := lerpf(_grid(x0, y0, z0),     _grid(x0 + 1, y0, z0),     fx)
    var c10 := lerpf(_grid(x0, y0 + 1, z0), _grid(x0 + 1, y0 + 1, z0), fx)
    var c01 := lerpf(_grid(x0, y0, z0 + 1), _grid(x0 + 1, y0, z0 + 1), fx)
    var c11 := lerpf(_grid(x0, y0 + 1, z0 + 1), _grid(x0 + 1, y0 + 1, z0 + 1), fx)
    return lerpf(lerpf(c00, c10, fy), lerpf(c01, c11, fy), fz)
