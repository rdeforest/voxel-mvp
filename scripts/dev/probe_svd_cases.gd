extends SceneTree

# Measures MpmSim.debug_svd as F approaches singular: det U, σ₂ and reconstruction for
# R·diag(1, 1, ±ε)·Rᵀ and diag(1, 1, ±ε), plus rank ≤ 1. Evidence for
# docs/bugs/mpm-svd-ill-conditioned-u.md.
#
#   godot --path . --headless -s res://scripts/dev/probe_svd_cases.gd


func _initialize() -> void:
    var r := _rot()

    for e in [1e-3, 1e-4, 1e-5, 1e-6, 1e-7, 1e-8, 1e-9, 1e-12]:
        for sgn in [1.0, -1.0]:
            var d := Basis.from_scale(Vector3(1, 1, sgn * e))
            _report("R·diag(1,1,%s)·Rᵀ" % str(sgn * e), r * d * r.transposed())
            _report("R·diag(1,1,%s)" % str(sgn * e), r * d)

    _report("diag(1,1,0)", Basis.from_scale(Vector3(1, 1, 0)))
    _report("diag(1,0,0)", Basis.from_scale(Vector3(1, 0, 0)))
    _report("zero", Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO))
    quit()


func _report(label: String, f: Basis) -> void:
    var s := MpmSim.new().debug_svd(f)

    print("%-26s detF=%-24s detU=%-18s detV=%-6s s2=%-24s err=%s" % [label,
        String.num_scientific(f.determinant()), s.det_u, s.det_v,
        String.num_scientific(s.s2), String.num_scientific(s.error)])


func _rot() -> Basis:
    var c1 := 3.0 / 5.0
    var s1 := 4.0 / 5.0
    var c2 := 20.0 / 29.0
    var s2 := 21.0 / 29.0

    return Basis(Vector3(c1, s1, 0.0), Vector3(-s1 * c2, c1 * c2, s2), Vector3(s1 * s2, -c1 * s2, c2))
