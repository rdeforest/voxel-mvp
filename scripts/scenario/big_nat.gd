class_name BigNat

# Arbitrary-size natural numbers, just enough arithmetic for ExactDecimal to compare a decimal
# against a double exactly. Little-endian limbs in base 2^24, so a limb times anything below 2^39
# plus a carry stays inside an int64. Zero is the empty array; no value has a leading zero limb.

const LIMB_BITS := 24
const LIMB_MASK := (1 << LIMB_BITS) - 1

# The largest power of ten a limb may be multiplied by in one step, and its exponent.
const TEN_CHUNK      := 1000000
const TEN_CHUNK_EXP  := 6


static func from_int(value: int) -> PackedInt64Array:
    var out := PackedInt64Array()
    while value > 0:
        out.append(value & LIMB_MASK)
        value >>= LIMB_BITS
    return out


static func from_digits(digits: String) -> PackedInt64Array:
    var out := PackedInt64Array()
    var at  := 0
    while at < digits.length():
        var chunk := digits.substr(at, TEN_CHUNK_EXP)
        out = add_small(mul_small(out, 10 ** chunk.length()), chunk.to_int())
        at += TEN_CHUNK_EXP
    return out


static func pow10(exponent: int) -> PackedInt64Array:
    var out := from_int(1)
    while exponent >= TEN_CHUNK_EXP:
        out = mul_small(out, TEN_CHUNK)
        exponent -= TEN_CHUNK_EXP
    return mul_small(out, 10 ** exponent)


# `factor` must be below 2^39 (see the limb comment above).
static func mul_small(a: PackedInt64Array, factor: int) -> PackedInt64Array:
    var out   := PackedInt64Array()
    var carry := 0
    for limb in a:
        var v := limb * factor + carry
        out.append(v & LIMB_MASK)
        carry = v >> LIMB_BITS

    while carry > 0:
        out.append(carry & LIMB_MASK)
        carry >>= LIMB_BITS
    return _trimmed(out)


static func add_small(a: PackedInt64Array, addend: int) -> PackedInt64Array:
    var out   := a.duplicate()
    var carry := addend
    var i     := 0
    while carry > 0:
        if i == out.size():
            out.append(0)
        var v := out[i] + carry
        out[i] = v & LIMB_MASK
        carry  = v >> LIMB_BITS
        i += 1
    return out


static func mul(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
    if a.is_empty() or b.is_empty():
        return PackedInt64Array()
    var out := PackedInt64Array()
    out.resize(a.size() + b.size())
    out.fill(0)
    for i in a.size():
        var carry := 0
        for j in b.size():
            var v := out[i + j] + a[i] * b[j] + carry
            out[i + j] = v & LIMB_MASK
            carry      = v >> LIMB_BITS
        var k := i + b.size()
        while carry > 0:
            var v := out[k] + carry
            out[k] = v & LIMB_MASK
            carry  = v >> LIMB_BITS
            k += 1
    return _trimmed(out)


static func shl(a: PackedInt64Array, bits: int) -> PackedInt64Array:
    if a.is_empty() or bits == 0:
        return a
    var out := PackedInt64Array()
    out.resize(bits / LIMB_BITS)
    out.fill(0)
    out.append_array(a)
    return mul_small(out, 1 << (bits % LIMB_BITS))


# -1, 0 or 1 as a is below, equal to or above b.
static func compare(a: PackedInt64Array, b: PackedInt64Array) -> int:
    if a.size() != b.size():
        return -1 if a.size() < b.size() else 1
    for i in range(a.size() - 1, -1, -1):
        if a[i] != b[i]:
            return -1 if a[i] < b[i] else 1
    return 0


static func _trimmed(a: PackedInt64Array) -> PackedInt64Array:
    var n := a.size()
    while n > 0 and a[n - 1] == 0:
        n -= 1
    return a.slice(0, n)
