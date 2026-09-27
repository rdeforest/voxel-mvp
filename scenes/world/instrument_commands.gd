class_name InstrumentCommands
extends RefCounted

# Doc 22's instrument layer at the console: exact writes (`setcorners`, `setmaterial`, `stamp`) and
# named saves (`save`, `load`). A write is an Action with a step op (SetCornersAction,
# SetMaterialAction, StampAction), run through the normal EditStore write path with its edits
# credited to INSTRUMENT, and heard by the recorder at its validate() as a click is.
#
# Instruments bypass player safety. When a write buries the player or removes the ground under
# them (PlayerSafeAction.danger_of, the check a player edit is refused by), the player is switched
# to fly mode, with noclip when buried, and told so.
#
# Numbers are read exactly: each is the double nearest the decimal typed (ExactDecimal), not the
# console's own parse, which can land an ulp off.
# docs/roadmap/design/22-scenario-languages.md, The instrument layer.
# (Drafted by Claude, overnight 2026-09-27.)

# Every instrument write that reached validate(), before it executes (Player.action_validated's twin).
signal validated(action: Action, valid: bool)

const SETCORNERS_USAGE  := "usage: setcorners <x> <y> <z> <c0> ... <c7>"
const SETMATERIAL_USAGE := "usage: setmaterial <x> <y> <z> <material>"
const STAMP_USAGE       := "usage: stamp <box|cylinder|sphere> <add|subtract> <material> <x> <y> <z> <dims...> [<rx> <ry> <rz>]"

var host:       Node   # the World: save_game(), and the tree a load reloads
var edit_store: EditStoreManager
var integrity:  StructuralIntegrity
var player:     CharacterBody3D

var _problem := ""   # why the last parse failed


func register_all() -> void:
    for c in _table():
        if not LimboConsole.has_command(c[1]):
            LimboConsole.register_command(c[0], c[1], c[2])

func unregister_all() -> void:
    if not is_instance_valid(LimboConsole):
        return
    for c in _table():
        if LimboConsole.has_command(c[1]):
            LimboConsole.unregister_command(c[1])

func _table() -> Array:
    return [
        [setcorners,  "setcorners",  "Instrument: set a cell's 8 lattice corners to exact SDF values (negative = solid); corner k is cell + (k&1, k>>1&1, k>>2&1). Bypasses player safety. " + SETCORNERS_USAGE],
        [setmaterial, "setmaterial", "Instrument: set a cell's material. Bypasses player safety. " + SETMATERIAL_USAGE],
        [stamp,       "stamp",       "Instrument: stamp a CSG shape by numbers. dims: box = full size x y z, cylinder = radius height, sphere = radius; rotation in degrees about x, y, z (the CSG tool's). Bypasses player safety. " + STAMP_USAGE],
        [save_slot,   "save",        "Save the world (like F5, once it has settled). `save <name>` saves to its own slot, user://saves/<name>/. Usage: save [name]"],
        [load_slot,   "load",        "Load a save (like F9). `load <name>` loads the slot `save <name>` wrote. Usage: load [name]"],
    ]


# --- Exact writes ---

func setcorners(args := "") -> void:
    var nums := _numbers(args.split(" ", false))
    if _problem == "" and nums.size() != 3 + SetCornersAction.CORNERS:
        _problem = SETCORNERS_USAGE
    var cell := _cell(nums)
    if _problem != "":
        LimboConsole.error("setcorners: %s" % _problem)
        return

    write(SetCornersAction.new(cell, nums.slice(3), _context()), "setcorners")


func setmaterial(args := "") -> void:
    var words := args.split(" ", false)
    var nums  := _numbers(words.slice(0, 3))
    if _problem == "" and words.size() != 4:
        _problem = SETMATERIAL_USAGE
    var cell     := _cell(nums)
    var material := _material(words[3] if words.size() == 4 else "")
    if _problem != "":
        LimboConsole.error("setmaterial: %s" % _problem)
        return

    write(SetMaterialAction.new(cell, material, _context()), "setmaterial")


func stamp(args := "") -> void:
    var words := args.split(" ", false)
    if words.size() < 7:
        LimboConsole.error("stamp: %s" % STAMP_USAGE)
        return

    _problem = ""
    var kind     := _enum_word(words[0], CsgSdf.Shape, "shape")
    var op       := _enum_word(words[1], CsgState.Op, "mode")
    var material := _material(words[2])
    var nums     := _numbers(words.slice(3)) if _problem == "" else PackedFloat64Array()
    var action   := _stamp_action(kind, op, material, nums) if _problem == "" else null
    if _problem != "":
        LimboConsole.error("stamp: %s" % _problem)
        return

    write(action, "stamp")


# Position, then the shape's dims, then optionally a rotation: the dims count is the shape's own
# (CsgShape.from_sdf refuses any other), so the numbers split one way only.
func _stamp_action(kind: int, op: int, material: StringName, nums: PackedFloat64Array) -> StampAction:
    var position := Vector3(nums[0], nums[1], nums[2])
    var shape    := CsgShape.from_sdf(kind, nums.slice(3))
    var rotation := Vector3.ZERO
    if shape == null and nums.size() >= 7:
        var at   := nums.size() - 3
        shape    = CsgShape.from_sdf(kind, nums.slice(3, at))
        rotation = Vector3(nums[at], nums[at + 1], nums[at + 2])
    if shape == null:
        _problem = "wrong count of numbers for a %s. %s" % [StepFields.enum_name(CsgSdf.Shape, kind), STAMP_USAGE]
        return null

    var xform := Transform3D(VoxelUtils.euler_basis(rotation), position)
    return StampAction.new(shape, xform, op, material, _context())


# The one path every instrument write takes: validate() (which the recorder hears), the write, then
# the rescue. The danger is read from the field before it is written, as a player edit's refusal is.
# `action` is a SetCornersAction, SetMaterialAction or StampAction: each has refusal() and
# written_field(), and they share no base below PlayerSafeAction to declare them on.
func write(action: PlayerSafeAction, command: String) -> bool:
    var valid := action.validate()
    validated.emit(action, valid)
    if not valid:
        LimboConsole.error("%s: refused, %s" % [command, action.call(&"refusal")])
        return false

    var danger := action.danger_of(action.call(&"written_field"), edit_store.store)
    action.execute()
    LimboConsole.info("%s: written %s" % [command, StepJson.new().stringify(StepRegistry.step_of(action))])
    _rescue(danger, command)
    return true


func _rescue(danger: PlayerSafeAction.Danger, command: String) -> void:
    if danger == PlayerSafeAction.Danger.NONE:
        return

    var buried := danger == PlayerSafeAction.Danger.BURIES
    player.enter_fly(buried)
    LimboConsole.warn("%s: that write %s, so you're flying now%s (X lands)" % [command,
        "buried you" if buried else "took the ground from under you", ", with noclip to get out" if buried else ""])


func _context() -> ActionContext:
    return ActionContext.new(edit_store.store, player, integrity, EditSource.Kind.INSTRUMENT)


# --- Named saves ---

# Refused while the world is settling, as F5 is: a save doesn't hold in-flight work.
func save_slot(name := "") -> void:
    if not integrity.is_quiescent():
        LimboConsole.error("save: the world is still settling (`settle` forces it)")
        return

    var problem: String = host.save_game(name)
    if not problem.is_empty():
        LimboConsole.error("save: %s" % problem)
        return
    LimboConsole.info("save: saved to %s" % ProjectSettings.globalize_path(SaveSlot.dir_of(name)))


func load_slot(name := "") -> void:
    var problem := SaveSlot.request_load(name)
    if not problem.is_empty():
        LimboConsole.error("load: %s" % problem)
        return

    LimboConsole.info("load: loading %s" % ProjectSettings.globalize_path(SaveSlot.dir_of(name)))
    host.get_tree().reload_current_scene.call_deferred()


# --- Parsing ---

# Each word as the double its decimal denotes; clears _problem, or sets it at the first word that
# isn't a decimal.
func _numbers(words: PackedStringArray) -> PackedFloat64Array:
    _problem = ""
    var out := PackedFloat64Array()
    for word in words:
        var x := ExactDecimal.parse(word)
        if is_nan(x):
            _problem = "\"%s\" is not a number" % word
            return PackedFloat64Array()
        out.append(x)
    return out

# nums[0..2] as a cell; sets _problem unless they're whole numbers.
func _cell(nums: PackedFloat64Array) -> Vector3i:
    if _problem != "" or nums.size() < 3:
        return Vector3i.ZERO
    for i in 3:
        if nums[i] != floorf(nums[i]) or absf(nums[i]) >= float(1 << 31):
            _problem = "a cell is whole numbers; %s isn't" % ExactDecimal.format(nums[i])
            return Vector3i.ZERO
    return Vector3i(int(nums[0]), int(nums[1]), int(nums[2]))

func _material(word: String) -> StringName:
    for name in MaterialPalette.NAMES:
        if String(name).to_lower() == word.to_lower():
            return name
    if _problem == "":
        _problem = "\"%s\" is not a material (%s)" % [word, ", ".join(MaterialPalette.NAMES)]
    return &""

func _enum_word(word: String, keys: Dictionary, what: String) -> int:
    if keys.has(word.to_upper()):
        return keys[word.to_upper()]
    if _problem == "":
        _problem = "\"%s\" is not a %s (%s)" % [word, what, ", ".join(keys.keys().map(func(k: String) -> String: return k.to_lower()))]
    return 0
