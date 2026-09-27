extends GutTest

# Step files must give back every double bit for bit: a sub-ulp change to a recorded position can
# move a lattice decision, and a replay that drifts isn't a replay. The engine's JSON can't do that
# (it drops -0.0's sign, and its reader lands an ulp off for about a quarter of doubles: see
# ExactDecimal), so StepJson reads numbers itself. Test values are built from bit patterns, never
# typed as literals: GDScript's literal parser is the engine's lossy one, and it folds a literal
# -0.0 to +0.0 in some expressions (an argument, [-0.0][0]) but not others.

const RANDOM_SAMPLES := 4000


func _x(bits: int) -> float:
    return ExactDecimal.from_bits(bits)

func _neg_zero() -> float:
    return _x(1 << 63)

func _same_bits(a: float, b: float) -> bool:
    return ExactDecimal.bits_of(a) == ExactDecimal.bits_of(b)

func _round_trip(values: Array) -> Array:
    var sj := StepJson.new()
    var text := sj.stringify(values)
    assert_eq(sj.error, "", "writes")
    assert_true(sj.parse(text), "reads back: %s" % sj.error)
    return sj.data

# Index of the first value that didn't come back bit-identical, or -1.
func _first_changed(values: Array) -> int:
    var back := _round_trip(values)
    for i in values.size():
        if not _same_bits(values[i], back[i]):
            return i
    return -1


func _tricky() -> Array:
    return [
        _x(0x3FB999999999999A),   # 0.1
        _x(0x01A56E1FC2F8F359),   # 1e-300
        1.0 / 3.0,
        _neg_zero(),
        _x(0x0000000000000001),   # smallest subnormal
        _x(0x000FFFFFFFFFFFFF),   # largest subnormal
        _x(0x0010000000000000),   # smallest normal
        _x(0x7FEFFFFFFFFFFFFF),   # largest double
        _x(0x44B52D02C7E14AF6),   # 1e23, which the engine writes as 9.999999999999999e+22
        _x(0x3F71ACADAE147AE1),   # 0.004315069615840912, which the engine reads an ulp low
        -1.5,
        _x(0x4340000000000001),   # 2^53 + 2
    ]


func test_tricky_doubles_survive_exactly() -> void:
    var values := _tricky()
    var i := _first_changed(values)
    assert_eq(i, -1, "every tricky double reads back bit-identical (first change at %d: %s)" % [i, values[i] if i >= 0 else ""])

func test_negative_zero_keeps_its_sign() -> void:
    var back := _round_trip([_neg_zero(), 0.0])
    assert_true(_same_bits(back[0], _neg_zero()), "-0.0 reads back negative")
    assert_true(_same_bits(back[1], 0.0), "0.0 reads back positive")


# Random bit patterns over every exponent, a quarter of them subnormal, and as many values of the
# size positions and dimensions have.
func test_random_doubles_survive_exactly() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20260927
    var values := []
    for i in RANDOM_SAMPLES:
        var bits := ((rng.randi() & 0x7FEFFFFF) << 32) | rng.randi()
        if i % 4 == 0:
            bits &= 0x000FFFFFFFFFFFFF
        values.append(_x(bits))
        values.append(-rng.randf() * pow(10.0, rng.randi_range(-4, 4)))
    var i := _first_changed(values)
    assert_eq(i, -1, "%d random doubles read back bit-identical (first change at %d)" % [values.size(), i])


# Text a person or another tool wrote is read as a correctly rounding parser (Python's) reads it,
# including ties, the subnormal edge and overflow.
func test_decimal_text_rounds_correctly() -> void:
    var expected := {
        "0.004315069615840912":               0x3F71ACADAE147AE1,
        "9007199254740993":                   0x4340000000000000,   # a tie: to the even significand
        "2.4703282292062328e-324":            0x0000000000000001,   # just past half the smallest subnormal
        "2.4703282292062327e-324":            0x0000000000000000,   # just under it
        "2.2250738585072014e-308":            0x0010000000000000,   # the engine reads this as zero
        "1.7976931348623158e308":             0x7FEFFFFFFFFFFFFF,
        "123456789012345678901234567890e-20": 0x41D26580B487E6B7,
        "0.30000000000000001":                0x3FD3333333333333,   # not the shortest text for it
        "-0.0":                               1 << 63,
        "1.50":                               0x3FF8000000000000,
    }
    for text: String in expected:
        assert_eq(ExactDecimal.bits_of(ExactDecimal.parse(text)), expected[text], text)
    assert_eq(ExactDecimal.parse("1.7976931348623159e308"), INF, "past the largest double")


func test_integers_stay_integers_up_to_2_53() -> void:
    var back := _round_trip([StepJson.MAX_EXACT_INT, -7, 0])
    assert_eq(back[0], float(StepJson.MAX_EXACT_INT), "2^53 reads back exactly")
    assert_eq(back[1], -7.0)

func test_refuses_what_it_cannot_write_exactly() -> void:
    for bad: Variant in [StepJson.MAX_EXACT_INT + 1, NAN, INF, Vector3.ONE, {1: "a"}, PackedFloat64Array([1.0])]:
        var sj := StepJson.new()
        assert_eq(sj.stringify([bad]), "", "refuses %s" % [bad])
        assert_ne(sj.error, "", "and says why")


func test_numbers_inside_strings_are_not_numbers() -> void:
    var sj := StepJson.new()
    assert_true(sj.parse("{\"a \\\" 1.5\": \"2.5 \\\\\", \"b\": [0.1, -3e-5]}"), sj.error)
    assert_eq(sj.data["a \" 1.5"], "2.5 \\")
    assert_true(_same_bits(sj.data["b"][0], _x(0x3FB999999999999A)), "0.1 is the double 0.1")

# The engine keeps a duplicate key at its first position with its last value, so a number after it
# would be matched to the wrong key; any duplicate is refused, whatever it holds.
func test_duplicate_keys_are_refused() -> void:
    for text: String in [
        "{\"a\": 1.5, \"a\": 2.5}",
        "{\"a\": \"x\", \"b\": 1.5, \"a\": 2.5}",
        "{\"a\": {}, \"b\": 1, \"a\": {\"c\": 2}}",
        "{\"a\": \"x\", \"a\": \"y\"}",
        "[{\"k\": [{\"a\": 1, \"\\u0061\": 2}]}]",
    ]:
        var sj := StepJson.new()
        assert_false(sj.parse(text), "refuses %s" % text)
        assert_string_contains(sj.error, "duplicate key", text)

func test_the_same_key_in_different_objects_is_fine() -> void:
    var sj := StepJson.new()
    assert_true(sj.parse("[{\"a\": 1.5, \"b\": {\"a\": 0.25}}, {\"a\": 2.5, \"k\": \"a\"}]"), sj.error)
    assert_eq(sj.data, [{"a": 1.5, "b": {"a": 0.25}}, {"a": 2.5, "k": "a"}])


# An exponent too long for an int64 still says which side of the double range it is on.
func test_absurd_exponents_saturate_the_right_way() -> void:
    assert_eq(ExactDecimal.parse("10e99999999999999999999"), INF)
    assert_eq(ExactDecimal.parse("-10e+00000000000000000000099999999999999"), -INF)
    assert_true(_same_bits(ExactDecimal.parse("10e-99999999999999999999"), 0.0), "under the smallest subnormal")
    assert_true(_same_bits(ExactDecimal.parse("-10e-99999999999999999999"), _neg_zero()), "and keeps its sign")
    assert_true(_same_bits(ExactDecimal.parse("1e-0000000000000000000000000001"), _x(0x3FB999999999999A)), "leading zeros are not size")
    assert_false(StepJson.new().parse("[10e99999999999999999999]"), "a step can't hold it")
    assert_engine_error("Exponent too high", "the engine's JSON reader warns on it; ExactDecimal does not ask it")


func test_keys_are_sorted_and_deep_levels_stay_on_one_line() -> void:
    var text := StepJson.new().stringify({"b": [{"z": 1, "y": [0.5, _neg_zero()]}], "a": true}, "  ", 2)
    assert_eq(text, "{\n  \"a\": true,\n  \"b\": [\n    {\"y\": [0.5, -0.0], \"z\": 1}\n  ]\n}")
