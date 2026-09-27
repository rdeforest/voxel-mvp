extends SceneTree

# Per-number read cost of ExactDecimal.parse by magnitude class. Drafted by Claude, overnight 2026-09-27.

func _init() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 9
    for band in [[-8, 8], [-3, 3], [100, 300], [-300, -100]]:
        var texts := PackedStringArray()
        for i in 2000:
            texts.append(ExactDecimal.format(rng.randf() * pow(10.0, rng.randi_range(band[0], band[1]))))
        var t0 := Time.get_ticks_usec()
        var slow := 0
        for t in texts:
            if t.to_float() != ExactDecimal.parse(t):
                slow += 1
            ExactDecimal.parse(t)
        print("band %s: %.1f us/number (2 parses), engine wrong on %d/%d" % [band, float(Time.get_ticks_usec() - t0) / texts.size(), slow, texts.size()])
    quit()
