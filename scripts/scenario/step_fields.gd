class_name StepFields
extends RefCounted

# The JSON shapes of a step's values, both ways. The static encoders turn engine values into the
# plain data StepJson writes; an instance reads one step back, strictly: a missing, mistyped or
# unread field is an error, so a step never half-decodes into a different action.
#
# Shapes:
#   Vector3     [x, y, z]
#   Vector3i    [x, y, z], each an integer
#   Transform3D {"basis": [[x], [y], [z]], "origin": [x, y, z]}; the three basis vectors are
#               Godot's basis.x/.y/.z, the images of the local axes (the matrix's columns)
#   enum value  its key, lower case ("box", "subtract")
#   material    its MaterialPalette name ("Stone")
#   count       a whole number >= 0 (frames)
#   flag        true / false

const _CELL_MIN := -(1 << 31)
const _CELL_MAX := (1 << 31) - 1

var error: String = ""

var _step: Dictionary
var _read: Dictionary = {}


func _init(step: Dictionary) -> void:
    _step = step


# --- Encoding ---

static func encode_vec3(v: Vector3) -> Array:
    return [v.x, v.y, v.z]

static func encode_cell(c: Vector3i) -> Array:
    return [c.x, c.y, c.z]

static func encode_xform(t: Transform3D) -> Dictionary:
    return {
        "basis":  [encode_vec3(t.basis.x), encode_vec3(t.basis.y), encode_vec3(t.basis.z)],
        "origin": encode_vec3(t.origin),
    }

static func encode_floats(values: PackedFloat64Array) -> Array:
    return Array(values)

static func enum_name(keys: Dictionary, value: int) -> String:
    return String(keys.find_key(value)).to_lower()


# --- Decoding ---

func number(key: String) -> float:
    var v: Variant = _take(key)
    if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
        _fail("%s: expected a number, got %s" % [key, v])
        return 0.0
    return float(v)

# A whole number of at least zero (a frame count); JSON reads every number as a double.
func count(key: String) -> int:
    var v: Variant = _take(key)
    if (typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT) or v != floorf(v) or v < 0 or v > _CELL_MAX:
        _fail("%s: expected a count, got %s" % [key, v])
        return 0
    return int(v)

func flag(key: String) -> bool:
    var v: Variant = _take(key)
    if typeof(v) != TYPE_BOOL:
        _fail("%s: expected true or false, got %s" % [key, v])
        return false
    return v

func text(key: String) -> String:
    var v: Variant = _take(key)
    if typeof(v) != TYPE_STRING and typeof(v) != TYPE_STRING_NAME:
        _fail("%s: expected a string, got %s" % [key, v])
        return ""
    return String(v)

func vec3(key: String) -> Vector3:
    return _vec3_of(key, _take(key))

func cell(key: String) -> Vector3i:
    var v := _floats_of(key, _take(key), 3)
    for x in v:
        if x != floorf(x) or x < _CELL_MIN or x > _CELL_MAX:
            _fail("%s: %s is not a 32-bit integer" % [key, x])
            return Vector3i.ZERO
    return Vector3i(int(v[0]), int(v[1]), int(v[2])) if v.size() == 3 else Vector3i.ZERO

func floats(key: String) -> PackedFloat64Array:
    return _floats_of(key, _take(key), -1)

func xform(key: String) -> Transform3D:
    var v: Variant = _take(key)
    if typeof(v) != TYPE_DICTIONARY or v.size() != 2 or not v.has("basis") or not v.has("origin"):
        _fail("%s: expected {\"basis\", \"origin\"}, got %s" % [key, v])
        return Transform3D.IDENTITY
    var axes: Variant = v["basis"]
    if typeof(axes) != TYPE_ARRAY or axes.size() != 3:
        _fail("%s.basis: expected three vectors, got %s" % [key, axes])
        return Transform3D.IDENTITY
    var basis := Basis(_vec3_of(key, axes[0]), _vec3_of(key, axes[1]), _vec3_of(key, axes[2]))
    return Transform3D(basis, _vec3_of(key, v["origin"]))

func enum_value(key: String, keys: Dictionary) -> int:
    var name := text(key)
    if not keys.has(name.to_upper()) or name != name.to_lower():
        _fail("%s: \"%s\" is not one of %s" % [key, name, keys.keys().map(func(k: String) -> String: return k.to_lower())])
        return 0
    return keys[name.to_upper()]

func material(key: String) -> StringName:
    var name := StringName(text(key))
    if not MaterialPalette.NAMES.has(name):
        _fail("%s: \"%s\" is not a material" % [key, name])
    return name


# Records a failure the reader can't see from the shapes alone (a part whose file changed).
func fail(message: String) -> void:
    _fail(message)


# Every field present was read. Call after decoding; an extra field is a format mismatch.
func check_all_read() -> void:
    for key: String in _step:
        if not _read.has(key):
            _fail("%s: not a field of this step" % key)


# --- Internals ---

func _take(key: String) -> Variant:
    _read[key] = true
    if not _step.has(key):
        _fail("%s: missing" % key)
        return null
    return _step[key]

func _vec3_of(key: String, v: Variant) -> Vector3:
    var f := _floats_of(key, v, 3)
    return Vector3(f[0], f[1], f[2]) if f.size() == 3 else Vector3.ZERO

# `length` -1 accepts any length.
func _floats_of(key: String, v: Variant, length: int) -> PackedFloat64Array:
    if typeof(v) != TYPE_ARRAY or (length >= 0 and v.size() != length):
        _fail("%s: expected %s numbers, got %s" % [key, "a list of" if length < 0 else str(length), v])
        return PackedFloat64Array()
    var out := PackedFloat64Array()
    for x: Variant in v:
        if typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT:
            _fail("%s: %s is not a number" % [key, x])
            return PackedFloat64Array()
        out.append(float(x))
    return out

func _fail(message: String) -> void:
    if error == "":
        error = message
