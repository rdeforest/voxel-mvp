extends SceneTree

# Is Vector3.normalized() idempotent on this engine? Drafted by Claude, overnight 2026-09-27.

func _init() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 3
    var moved := 0
    var first := Vector3.ZERO
    for i in 100000:
        var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
        var n := v.normalized()
        if n.normalized() != n:
            moved += 1
            if first == Vector3.ZERO:
                first = v
    print("renormalizing moved %d/100000; first input %s bits %x %x %x" % [moved, first, ExactDecimal.bits_of(first.x), ExactDecimal.bits_of(first.y), ExactDecimal.bits_of(first.z)])
    print("real_t is double: ", Vector3(0.1, 0, 0).x == 0.1)
    quit()
