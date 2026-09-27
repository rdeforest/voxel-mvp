extends SceneTree

# How often a random double survives each of Godot's text encodings exactly. Run headless with -s.
# (Drafted by Claude, overnight 2026-09-27; evidence for doc 22's JSON-numbers note.)

const SAMPLES := 100000


func _init() -> void:
    var encodings := {
        "var_to_str":          func(x: float) -> float: return str_to_var(var_to_str(x)),
        "JSON full_precision": func(x: float) -> float: return JSON.parse_string(JSON.stringify([x], "", true, true))[0],
        "var_to_bytes":        func(x: float) -> float: return bytes_to_var(var_to_bytes(x)),
    }
    for name: String in encodings:
        var misses := 0
        for i in SAMPLES:
            var x := randf() * pow(10.0, randi_range(-8, 8))
            if encodings[name].call(x) != x:
                misses += 1
        print("%s: %d/%d read back inexactly" % [name, misses, SAMPLES])
    quit()
