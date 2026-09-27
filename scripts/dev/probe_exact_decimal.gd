extends SceneTree

# Exactness and speed of StepJson/ExactDecimal against the engine's JSON over random doubles of
# every exponent, subnormals included. Drafted by Claude, overnight 2026-09-27.

func _init() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 5
    var xs: Array[float] = []
    for i in 20000:
        var bits := ((rng.randi() & 0x7FEFFFFF) << 32) | rng.randi()
        if i % 4 == 0:
            bits &= 0x000FFFFFFFFFFFFF
        if i % 2 == 1:
            bits = ExactDecimal.bits_of(rng.randf() * pow(10.0, rng.randi_range(-8, 8)))
        xs.append(ExactDecimal.from_bits(bits))
    var sj := StepJson.new()
    var t0 := Time.get_ticks_usec()
    var text := sj.stringify(xs)
    var t1 := Time.get_ticks_usec()
    var ok := sj.parse(text)
    var t2 := Time.get_ticks_usec()
    var back: Array = sj.data
    var miss := 0
    for i in xs.size():
        if ExactDecimal.bits_of(back[i]) != ExactDecimal.bits_of(xs[i]):
            miss += 1
    var engine: Array = JSON.parse_string(JSON.stringify(xs, "", false, true))
    var emiss := 0
    for i in xs.size():
        if ExactDecimal.bits_of(engine[i]) != ExactDecimal.bits_of(xs[i]):
            emiss += 1
    print("StepJson ok=%s misses %d/%d  write %d us  read %d us" % [ok, miss, xs.size(), t1 - t0, t2 - t1])
    print("engine JSON misses %d/%d" % [emiss, xs.size()])
    quit()
