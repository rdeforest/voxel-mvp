class_name SdfAnalytic
extends SdfField

# Field backed by an analytic SDF callable. Gradients are exact finite
# differences with a tiny step, so creases stay crisp. The surface nudge keeps
# samples that land exactly on the surface a hair inside, so a surface
# coincident with grid samples doesn't degenerate (see DualContour).

const NUDGE := -1e-6
const EPS   := 0.001

var _fn: Callable


func _init(fn: Callable) -> void:
    _fn = fn

func value(p: Vector3) -> float:
    var v := float(_fn.call(p))
    return v if v != 0.0 else NUDGE

func gradient(p: Vector3) -> Vector3:
    var dx := float(_fn.call(p + Vector3(EPS, 0, 0))) - float(_fn.call(p - Vector3(EPS, 0, 0)))
    var dy := float(_fn.call(p + Vector3(0, EPS, 0))) - float(_fn.call(p - Vector3(0, EPS, 0)))
    var dz := float(_fn.call(p + Vector3(0, 0, EPS))) - float(_fn.call(p - Vector3(0, 0, EPS)))
    var g := Vector3(dx, dy, dz)
    return g.normalized() if g.length_squared() > 0.0 else Vector3.UP
