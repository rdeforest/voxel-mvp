class_name StepJson
extends RefCounted

# JSON for step files, exact for every double (ExactDecimal says why the engine's JSON isn't). The
# text is ordinary JSON any reader takes; only numbers are handled here. Values are null, bool,
# int (|i| <= 2^53: JSON has one number type and it reads back as a double), finite float, String
# or StringName, Array, and Dictionary with String keys, which are written sorted. Anything else
# is refused, not coerced, so a vector must be encoded (StepFields) before it gets here.
#
# Reading lets the engine's parser build the structure, then puts back every number from its own
# text, in document order. Any duplicate key is refused: the engine keeps a duplicate at its first
# position with its last value, so its walk order stops being document order and numbers would
# land on the wrong keys.

const MAX_EXACT_INT := 1 << 53

var data:  Variant
var error: String = ""


# `indent` "" writes one line. Otherwise containers nested deeper than `wrap_depth` still go on
# one line (-1: wrap every level) — a step per line, so trimming a recording is deleting lines.
func stringify(value: Variant, indent: String = "", wrap_depth: int = -1) -> String:
    error = ""
    var out := _emit(value, indent, wrap_depth, 0)
    return "" if error != "" else out


func parse(text: String) -> bool:
    error = ""
    data  = null
    var json := JSON.new()
    if json.parse(text) != OK:
        error = "line %d: %s" % [json.get_error_line(), json.get_error_message()]
        return false

    var texts := _number_texts(text)
    if error != "":
        return false
    var at: Array[int] = [0]
    var restored: Variant = _restore(json.data, texts, at)
    if at[0] != texts.size():
        _fail("%d numbers in the text, %d in the structure" % [texts.size(), at[0]])
    if error != "":
        return false
    data = restored
    return true


# --- Writing ---

func _emit(value: Variant, indent: String, wrap_depth: int, depth: int) -> String:
    match typeof(value):
        TYPE_NIL:
            return "null"
        TYPE_BOOL:
            return "true" if value else "false"
        TYPE_INT:
            if absi(value) > MAX_EXACT_INT:
                _fail("%d is past 2^53 and would not read back exactly" % value)
            return str(value)
        TYPE_FLOAT:
            if not is_finite(value):
                _fail("%s has no JSON form" % value)
                return ""
            return ExactDecimal.format(value)
        TYPE_STRING, TYPE_STRING_NAME:
            return JSON.stringify(String(value))
        TYPE_ARRAY:
            return _emit_array(value, indent, wrap_depth, depth)
        TYPE_DICTIONARY:
            return _emit_dict(value, indent, wrap_depth, depth)
    _fail("a %s can't be written; encode it first" % type_string(typeof(value)))
    return ""


func _emit_array(values: Array, indent: String, wrap_depth: int, depth: int) -> String:
    var parts := PackedStringArray()
    for v: Variant in values:
        parts.append(_emit(v, indent, wrap_depth, depth + 1))
    return _join(parts, "[", "]", indent, wrap_depth, depth)


func _emit_dict(values: Dictionary, indent: String, wrap_depth: int, depth: int) -> String:
    var keys := values.keys()
    for k: Variant in keys:
        if typeof(k) != TYPE_STRING:
            _fail("key %s is not a String" % [k])
            return ""
    keys.sort()
    var parts := PackedStringArray()
    for k: String in keys:
        parts.append("%s: %s" % [JSON.stringify(k), _emit(values[k], indent, wrap_depth, depth + 1)])
    return _join(parts, "{", "}", indent, wrap_depth, depth)


func _join(parts: PackedStringArray, open: String, close: String, indent: String,
        wrap_depth: int, depth: int) -> String:
    if parts.is_empty():
        return open + close
    var inline := indent == "" or (wrap_depth >= 0 and depth >= wrap_depth)
    if inline:
        return open + ", ".join(parts) + close
    var inner := "\n" + indent.repeat(depth + 1)
    return open + inner + ("," + inner).join(parts) + "\n" + indent.repeat(depth) + close


# --- Reading ---

# The text of every number token, in document order, skipping string literals; refuses a duplicate
# key. The engine already accepted `text`, so the scan can trust its grammar.
func _number_texts(text: String) -> PackedStringArray:
    var out  := PackedStringArray()
    var open := []   # per open container: its key set (an object) or null (an array)
    var i    := 0
    var n    := text.length()
    while i < n:
        var c := text[i]
        if c == "{" or c == "[":
            open.push_back({} if c == "{" else null)
        elif c == "}" or c == "]":
            open.pop_back()
        elif c == "\"":
            var end := _string_end(text, i)
            if not open.is_empty() and open.back() != null and _next_is_colon(text, end + 1):
                _add_key(open.back(), text.substr(i, end - i + 1))
            i = end
        elif c == "-" or (c >= "0" and c <= "9"):
            var start := i
            while i < n and "0123456789+-.eE".contains(text[i]):
                i += 1
            out.append(text.substr(start, i - start))
            continue
        i += 1
    return out

static func _next_is_colon(text: String, from: int) -> bool:
    var i := from
    while i < text.length() and " \t\n\r".contains(text[i]):
        i += 1
    return i < text.length() and text[i] == ":"

# Keys are compared decoded, so "a" and "\u0061" are the same key.
func _add_key(keys: Dictionary, literal: String) -> void:
    var key: String = JSON.parse_string(literal)
    if keys.has(key):
        _fail("duplicate key %s" % JSON.stringify(key))
    keys[key] = true

# Index of the closing quote of the string literal opening at `start`.
static func _string_end(text: String, start: int) -> int:
    var i := start + 1
    while text[i] != "\"":
        i += 2 if text[i] == "\\" else 1
    return i


func _restore(value: Variant, texts: PackedStringArray, at: Array[int]) -> Variant:
    match typeof(value):
        TYPE_FLOAT:
            return _exact(texts, at)
        TYPE_ARRAY:
            var out := []
            for v: Variant in value:
                out.append(_restore(v, texts, at))
            return out
        TYPE_DICTIONARY:
            var out := {}
            for k: String in value:
                out[k] = _restore(value[k], texts, at)
            return out
    return value


func _exact(texts: PackedStringArray, at: Array[int]) -> float:
    if at[0] >= texts.size():
        _fail("a number's text is missing (duplicate key?)")
        return NAN
    var x := ExactDecimal.parse(texts[at[0]])
    if not is_finite(x):
        _fail("%s is not a finite double" % texts[at[0]])
    at[0] += 1
    return x


# The first failure is the one worth reporting; later ones are usually its echoes.
func _fail(message: String) -> void:
    if error == "":
        error = message
