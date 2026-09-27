class_name ExactDecimal

# Decimal text <-> double with no loss, for step files (docs/roadmap/design/22-scenario-languages.md,
# "JSON numbers"). Writing is the engine's: JSON.stringify's full_precision text is the shortest
# decimal that reads back as the same double under a correctly rounded parser (checked against
# Python on 200,000 doubles across every exponent, scripts/dev/probe_grisu_vs_python.gd). Reading
# is not: the engine's own parser (String::to_float, which JSON and GDScript literals share) lands
# an ulp off for about a quarter of those texts and reads 2.2250738585072014e-308 as zero. So
# parse() rounds correctly itself: it brackets the double the text denotes, starting from the
# engine's guess, and compares candidates against the text exactly in big integers.

const _SIGN_BIT    := 1 << 63
const _FRAC_BITS   := 52
const _FRAC_MASK   := (1 << _FRAC_BITS) - 1
const _INF_BITS    := 0x7FF0000000000000
const _EXP_BIAS    := 1075   # exponent field minus this = exponent of the integer significand
const _SUBNORMAL_E := -1074

# Decimal exponents (of the leading digit) past which the answer is known without arithmetic:
# above 1e309 is past the largest double, below 1e-325 is under half the smallest subnormal.
const _TOO_BIG   := 309
const _TOO_SMALL := -325

# A written exponent past this is read as this: still far outside the double range, whatever the
# digit count, and the offsets _decimal_of adds to it can't wrap an int64.
const _EXPONENT_CLAMP := 1_000_000_000

static var _grammar := RegEx.create_from_string("^(-?)(\\d+)(?:\\.(\\d+))?(?:[eE]([+-]?\\d+))?$")


static func format(x: float) -> String:
    if x == 0.0:
        return "-0.0" if bits_of(x) & _SIGN_BIT else "0.0"
    return JSON.stringify(x, "", false, true)


# The double nearest the decimal `text` (JSON number grammar), ties to even. NaN if `text` isn't a
# decimal; +-INF if it's beyond the largest double.
#
# The engine's guess is taken as is when format() writes it back as this same decimal: format()'s
# text reads back correctly rounded to the double it came from (the writer's own guarantee), so the
# guess is that double. Only the rest pay for big-integer rounding.
static func parse(text: String) -> float:
    var d := _decimal_of(text)
    if d.is_empty():
        return NAN
    var guess := 0.0 if _out_of_range(d[1], d[2]) else text.to_float()
    if is_finite(guess) and _decimal_of(format(guess)) == d:
        return guess

    var magnitude := _magnitude_bits(d[1], d[2], absf(guess))
    return from_bits(magnitude | (_SIGN_BIT if d[0] else 0))


# [negative, digits, exponent] with value digits * 10^exponent and no leading or trailing zero in
# digits (zero: empty digits), so equal values have equal forms. [] if `text` isn't a decimal.
static func _decimal_of(text: String) -> Array:
    var m := _grammar.search(text)
    if m == null:
        return []
    var frac     := m.get_string(3)
    var digits   := (m.get_string(2) + frac).lstrip("0")
    var trimmed  := digits.rstrip("0")
    var exponent := _exponent_of(m.get_string(4)) - frac.length() + digits.length() - trimmed.length()
    return [m.get_string(1) == "-", trimmed, exponent if not trimmed.is_empty() else 0]


static func _exponent_of(text: String) -> int:
    if text.lstrip("+-").lstrip("0").length() > 9:
        return -_EXPONENT_CLAMP if text.begins_with("-") else _EXPONENT_CLAMP
    return clampi(text.to_int(), -_EXPONENT_CLAMP, _EXPONENT_CLAMP)


static func bits_of(x: float) -> int:
    var buf := PackedByteArray()
    buf.resize(8)
    buf.encode_double(0, x)
    return buf.decode_s64(0)

static func from_bits(bits: int) -> float:
    var buf := PackedByteArray()
    buf.resize(8)
    buf.encode_s64(0, bits)
    return buf.decode_double(0)


# --- Correct rounding ---

# Bits of the non-negative double nearest digits * 10^exponent (digits: no leading or trailing
# zeros), given an estimate near it.
static func _magnitude_bits(digits: String, exponent: int, estimate: float) -> int:
    if digits.is_empty():
        return 0
    if _out_of_range(digits, exponent):
        return _INF_BITS if digits.length() - 1 + exponent >= _TOO_BIG else 0

    var d := _Decimal.new(digits, exponent)
    var below := _last_at_or_below(d, mini(bits_of(estimate), _INF_BITS))
    if below == _INF_BITS:
        return _INF_BITS

    var mid  := _midpoint(below)
    var side := d.compare(mid[0], mid[1])
    if side == 0:
        return below if below & 1 == 0 else below + 1
    return below + 1 if side > 0 else below


# Past the largest double or under half the smallest subnormal, by the leading digit's exponent.
# The engine's parser is not asked about these: it warns on them.
static func _out_of_range(digits: String, exponent: int) -> bool:
    var lead := digits.length() - 1 + exponent
    return not digits.is_empty() and (lead >= _TOO_BIG or lead < _TOO_SMALL)


# The largest bit pattern whose double is <= d. Patterns of non-negative doubles order like their
# values, so this gallops out from the estimate to a bracket and bisects it; _INF_BITS stands for
# 2^1024, the value the next pattern past the largest finite double would have.
static func _last_at_or_below(d: _Decimal, start: int) -> int:
    var lo   := start
    var hi   := start
    var step := 1
    if d.at_least_bits(start):
        hi = mini(lo + step, _INF_BITS)
        while hi < _INF_BITS and d.at_least_bits(hi):
            lo = hi
            step *= 2
            hi = mini(lo + step, _INF_BITS)
        if hi == _INF_BITS and d.at_least_bits(hi):
            return _INF_BITS
    else:
        lo = maxi(hi - step, 0)
        while lo > 0 and not d.at_least_bits(lo):
            hi = lo
            step *= 2
            lo = maxi(hi - step, 0)

    while hi - lo > 1:
        var probe := lo + (hi - lo) / 2
        if d.at_least_bits(probe):
            lo = probe
        else:
            hi = probe
    return lo


# [significand, exponent] of the value halfway between pattern `bits` and the next one up.
static func _midpoint(bits: int) -> Array[int]:
    var a := _parts(bits)
    var b := _parts(bits + 1)
    var e := mini(a[1], b[1])
    return [(a[0] << (a[1] - e)) + (b[0] << (b[1] - e)), e - 1]


# [integer significand, binary exponent] of a non-negative pattern, value = significand * 2^exponent.
static func _parts(bits: int) -> Array[int]:
    var field := bits >> _FRAC_BITS
    var frac  := bits & _FRAC_MASK
    if field == 0:
        return [frac, _SUBNORMAL_E]
    return [frac | (1 << _FRAC_BITS), field - _EXP_BIAS]


# digits * 10^exponent, held as the big integers the exact comparison multiplies out.
class _Decimal:
    var _scaled:   PackedInt64Array   # digits * 10^max(exponent, 0)
    var _divisor:  PackedInt64Array   # 10^max(-exponent, 0)

    func _init(digits: String, exponent: int) -> void:
        _scaled  = BigNat.mul(BigNat.from_digits(digits), BigNat.pow10(maxi(exponent, 0)))
        _divisor = BigNat.pow10(maxi(-exponent, 0))

    # Sign of (this - significand * 2^exponent).
    func compare(significand: int, exponent: int) -> int:
        var lhs := BigNat.shl(_scaled, maxi(-exponent, 0))
        var rhs := BigNat.shl(BigNat.mul(_divisor, BigNat.from_int(significand)), maxi(exponent, 0))
        return BigNat.compare(lhs, rhs)

    func at_least_bits(bits: int) -> bool:
        var p := ExactDecimal._parts(bits)
        return compare(p[0], p[1]) >= 0
