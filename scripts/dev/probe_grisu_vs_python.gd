extends SceneTree

# Is the engine's float WRITER exact? Dumps "<bits> <JSON full_precision text>" for 200,000 random
# doubles (every exponent, a quarter subnormal) to res://tmp/grisu.txt; then check them with a
# correctly rounding parser:
#   python3 -c "import struct,sys; print(sum(t!='0.0' and struct.unpack('<q',struct.pack('<d',float(t)))[0]!=int(b) for b,t in (l.split() for l in open(sys.argv[1]))))" tmp/grisu.txt
# 0 on 2026-09-27 (4.6, double build). Drafted by Claude, overnight 2026-09-27.

func _init() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 11
    var f := FileAccess.open("res://tmp/grisu.txt", FileAccess.WRITE)
    for i in 200000:
        var bits := ((rng.randi() & 0x7FEFFFFF) << 32) | rng.randi()
        if i % 4 == 0:
            bits &= 0x000FFFFFFFFFFFFF
        f.store_line("%d %s" % [bits, JSON.stringify(ExactDecimal.from_bits(bits), "", false, true)])
    f.close()
    quit()
