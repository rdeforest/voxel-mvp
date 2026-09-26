extends SceneTree

# Dumps the seeded random F of test/test_mpm_svd.gd (generator copied verbatim) at full precision,
# so a line-for-line port of Mat3::svd can classify which reflection branch each one reaches. The
# "E" lines are the engine's debug_svd output on the same F, for checking the port against it.
#
#   godot --path . --headless -s res://scripts/dev/dump_svd_random_inputs.gd


func _initialize() -> void:
    var r  := _rot()
    var rt := r.transposed()
    var e  := Basis.from_euler(Vector3(0.3, 0.5, 0.7))
    var fixed := {
        "nf diag(2,1,.5)": _st(2, 1, 0.5), "nf diag(1,.5,2)": _st(1, 0.5, 2),
        "bf R": r, "bf diag(.5,1,2)": _st(0.5, 1, 2), "bf R.diag(.5,1,2)": r * _st(0.5, 1, 2), "bf R.diag(2,1,.5)": r * _st(2, 1, 0.5),
        "uf diag(2,1,-.5)": _st(2, 1, -0.5), "uf diag(-1,.5,2)": _st(-1, 0.5, 2), "uf -I": _st(-1, -1, -1),
        "vf diag(-.5,1,2)": _st(-0.5, 1, 2), "vf diag(1,-2,.5)": _st(1, -2, 0.5), "vf R.diag(2,1,-.5)": r * _st(2, 1, -0.5), "vf R.diag(-.5,1,2)": r * _st(-0.5, 1, 2),
        "eu I": Basis.IDENTITY, "eu E": e, "eu Es": e.scaled(Vector3(3, 1.5, 0.7)), "eu Er": e.scaled(Vector3(3, 1.5, -0.7)),
        "rp 2,2,.5": r * _st(2, 2, 0.5) * rt, "rp 2,.5,.5": r * _st(2, 0.5, 0.5) * rt, "rp 2,.5,-.5": r * _st(2, 0.5, -0.5) * rt, "rp 1,1,-1": r * _st(1, 1, -1) * rt, "rp -R": r * -1.0,
        "ns 1e-3": r * _st(1, 1, 1e-3) * rt, "ns -1e-3": r * _st(1, 1, -1e-3) * rt, "ns 1,1e-3,1e-3": r * _st(1, 1e-3, 1e-3) * rt,
    }
    for k in fixed:
        _dump(k.replace(" ", "_"), fixed[k])
    var rng := RandomNumberGenerator.new()
    rng.seed = 20260926
    for i in 64:
        var reflected := i % 2 == 1
        _dump("rrr%d" % i, _random_rotation(rng) * _random_stretch(rng, reflected) * _random_rotation(rng))

    rng = RandomNumberGenerator.new()
    rng.seed = 1597
    for i in 32:
        var f := Basis()
        for c in 3:
            f[c] = Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
        _dump("gen%d" % i, f)
    quit()


func _st(x: float, y: float, z: float) -> Basis:
    return Basis.from_scale(Vector3(x, y, z))


func _rot() -> Basis:
    var c1 := 3.0 / 5.0
    var s1 := 4.0 / 5.0
    var c2 := 20.0 / 29.0
    var s2 := 21.0 / 29.0
    return Basis(Vector3(c1, s1, 0.0), Vector3(-s1 * c2, c1 * c2, s2), Vector3(s1 * s2, -c1 * s2, c2))


func _dump(label: String, f: Basis) -> void:
    var out := PackedStringArray([label])
    for row in 3:
        for col in 3:
            out.append("%.20f" % f[col][row])
    print("F ", " ".join(out))

    var r := MpmSim.new().debug_svd(f)
    var e := PackedStringArray([label])
    for key in ["det_u", "det_v", "s0", "s1", "s2", "error"]:
        e.append("%.20f" % r[key])
    print("E ", " ".join(e))


func _random_rotation(rng: RandomNumberGenerator) -> Basis:
    var q := Quaternion(rng.randfn(), rng.randfn(), rng.randfn(), rng.randfn()).normalized()
    return Basis(q)


func _random_stretch(rng: RandomNumberGenerator, reflected: bool) -> Basis:
    var s := Vector3(rng.randf_range(0.2, 3.0), rng.randf_range(0.2, 3.0), rng.randf_range(0.2, 3.0))
    if reflected:
        s[rng.randi_range(0, 2)] *= -1.0
    return Basis.from_scale(s)
