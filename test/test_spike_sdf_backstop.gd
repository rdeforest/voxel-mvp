extends GutTest

# SPIKE (Exp 1): does an SDF depenetration backstop hold a fast-falling body out
# of solid without tunneling or jitter — the claim that "correctness never depends
# on the cooked collision shape"? Headless numerical drop test against three fields:
#   - a unit-distance plane (clean baseline),
#   - a sloped NON-unit-distance plane (models the terrain SDF gotcha: |sdf|
#     overestimates true distance on slopes — see dc-sdf-not-unit-distance),
#   - the real terrain SDF (baked, trilinear).
# For each: naive depenetration (push by raw |sdf|) vs corrected (push by the
# gradient-normalized distance |sdf|/|∇sdf|). Prints settle/overshoot/tunnel
# metrics; asserts the corrected method holds (no tunnel, settles).

const DT := 1.0 / 60.0
const GRAVITY := Vector3(0, -30, 0)     # fast fall
const RADIUS := 0.5                     # body sphere radius
const STEPS := 300
const GRAD_H := 0.1


func _f(f: Callable, p: Vector3) -> float:
    return f.call(p)

func _grad(f: Callable, p: Vector3) -> Vector3:
    var hx := Vector3(GRAD_H, 0, 0)
    var hy := Vector3(0, GRAD_H, 0)
    var hz := Vector3(0, 0, GRAD_H)
    return Vector3(
        _f(f, p + hx) - _f(f, p - hx),
        _f(f, p + hy) - _f(f, p - hy),
        _f(f, p + hz) - _f(f, p - hz)) / (2.0 * GRAD_H)

# Drop a sphere from `start`, depenetrating against field f each step. Returns
# {min_clear (most embedded the body got, after depenetration), settle_jitter
# (peak-to-peak y over the last 60 steps), final_y}.
func _drop(f: Callable, start: Vector3, corrected: bool) -> Dictionary:
    var c := start
    var v := Vector3.ZERO
    var min_clear := INF
    var ys := PackedFloat32Array()
    for _s in STEPS:
        v += GRAVITY * DT
        c += v * DT
        var g := _grad(f, c)
        var gl := g.length()
        if gl > 1e-6:
            var n := g / gl
            var raw := _f(f, c)
            var dist: float = (raw / gl) if corrected else raw   # gradient-normalized "true" distance
            if dist < RADIUS:
                c += n * (RADIUS - dist)
                var into := v.dot(n)
                if into < 0.0:
                    v -= into * n
        # measure clearance with the corrected distance (true-ish), independent of method
        var gg := _grad(f, c)
        var ggl := gg.length()
        var clear: float = (_f(f, c) / ggl if ggl > 1e-6 else _f(f, c)) - RADIUS
        min_clear = minf(min_clear, clear)
        ys.append(c.y)
    var lo := INF
    var hi := -INF
    for i in range(maxi(0, ys.size() - 60), ys.size()):
        lo = minf(lo, ys[i])
        hi = maxf(hi, ys[i])
    return {"min_clear": min_clear, "jitter": hi - lo, "final_y": c.y}

func _report(label: String, r: Dictionary) -> void:
    print("[sdf backstop] %-28s min_clear %+.3f  settle_jitter %.4f  final_y %.3f" % [
        label, r["min_clear"], r["jitter"], r["final_y"]])


# --- Fields ---

func _plane(p: Vector3) -> float:               # unit-distance: surface y=0
    return p.y

func _slope(p: Vector3) -> float:               # NON-unit: |grad| = sqrt(2); overestimates ~1.41x
    return p.y - p.x


# Baked real-terrain SDF (trilinear), matching world.tscn's generator.
var _t_data: PackedFloat32Array
var _t_dim := 65
var _t_origin := Vector3(-32, -32, -32)

func _bake_terrain() -> void:
    var noise := FastNoiseLite.new()
    noise.seed = 1
    noise.fractal_lacunarity = 1.5
    var gen := VoxelGeneratorNoise2D.new()
    gen.height_range = 100.0
    gen.noise = noise
    var buf := VoxelBuffer.new()
    buf.create(_t_dim, _t_dim, _t_dim)
    gen.generate_block(buf, _t_origin, 0)
    _t_data = PackedFloat32Array()
    _t_data.resize(_t_dim * _t_dim * _t_dim)
    var i := 0
    for z in _t_dim:
        for y in _t_dim:
            for x in _t_dim:
                _t_data[i] = buf.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
                i += 1

func _t_grid(x: int, y: int, z: int) -> float:
    x = clampi(x, 0, _t_dim - 1); y = clampi(y, 0, _t_dim - 1); z = clampi(z, 0, _t_dim - 1)
    return _t_data[x + _t_dim * (y + _t_dim * z)]

func _terrain(p: Vector3) -> float:
    var l := p - _t_origin
    var x0 := floori(l.x); var y0 := floori(l.y); var z0 := floori(l.z)
    var fx := l.x - x0; var fy := l.y - y0; var fz := l.z - z0
    var c00 := lerpf(_t_grid(x0, y0, z0),     _t_grid(x0+1, y0, z0),     fx)
    var c10 := lerpf(_t_grid(x0, y0+1, z0),   _t_grid(x0+1, y0+1, z0),   fx)
    var c01 := lerpf(_t_grid(x0, y0, z0+1),   _t_grid(x0+1, y0, z0+1),   fx)
    var c11 := lerpf(_t_grid(x0, y0+1, z0+1), _t_grid(x0+1, y0+1, z0+1), fx)
    return lerpf(lerpf(c00, c10, fy), lerpf(c01, c11, fy), fz)


# --- Tests ---

func test_unit_plane_holds():
    var r := _drop(_plane, Vector3(0, 20, 0), true)
    _report("unit plane (corrected)", r)
    assert_gt(r["min_clear"], -0.05, "no tunneling through the plane")
    assert_lt(r["jitter"], 0.05, "settles without jitter")

func test_sloped_nonunit_naive_vs_corrected():
    # An INFINITE frictionless ramp: a body correctly slides forever (no settling to
    # assert). What matters is staying ON the surface — corrected (f/|∇f|) holds the
    # body on the isosurface where naive (raw |sdf|) sinks into the non-unit field.
    var naive := _drop(_slope, Vector3(0, 20, 0), false)
    var corrected := _drop(_slope, Vector3(0, 20, 0), true)
    _report("slope NON-unit (naive)", naive)
    _report("slope NON-unit (corrected)", corrected)
    assert_gt(corrected["min_clear"], -0.05, "corrected: stays on the surface (no embed)")
    assert_gt(corrected["min_clear"], naive["min_clear"], "gradient-normalized beats raw |sdf|")

func test_real_terrain_holds():
    # The decisive claim: a fast body never embeds into the real (non-unit) terrain
    # SDF — the backstop holds while a collision tile would be cooking. (Resting/
    # friction is the cooked shape's job; here a frictionless sphere just slides
    # across slopes, which is correct, not a backstop failure.)
    _bake_terrain()
    var r := _drop(_terrain, Vector3(0, 40, 0), true)
    _report("real terrain (corrected)", r)
    assert_gt(r["min_clear"], -0.2, "no tunneling/embedding into terrain")
