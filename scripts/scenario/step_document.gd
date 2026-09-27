class_name StepDocument
extends RefCounted

# A step file: a header naming the format, its version and the units its plain numbers are in,
# then the steps, one per line. Recorded steps carry the engine's own values, so lengths are
# metres and angles degrees (ConstructionAction's rotation). Doc 22's unit strings ("5.5 foot") are
# for quantities a person writes; they arrive with the phase-3 evaluator, and a version that
# accepts them will say so here.

const FORMAT  := "voxel-mvp/steps"
const VERSION := 1
const UNITS   := {"length": "meter", "angle": "degree"}

const _INDENT := "  "
const _STEP_DEPTH := 2   # document -> "steps" array -> a step

var steps: Array[Dictionary] = []
var error: String = ""


func write() -> String:
    var sj := StepJson.new()
    var doc := {"format": FORMAT, "version": VERSION, "units": UNITS, "steps": steps}
    var text := sj.stringify(doc, _INDENT, _STEP_DEPTH)
    error = sj.error
    return text + "\n" if error == "" else ""


func read(text: String) -> bool:
    error = ""
    steps = []
    var sj := StepJson.new()
    if not sj.parse(text):
        error = sj.error
        return false
    var doc: Variant = sj.data
    var refusal := _header_refusal(doc)
    if refusal != "":
        error = refusal
        return false
    for step: Variant in doc["steps"]:
        if typeof(step) != TYPE_DICTIONARY:
            error = "steps: %s is not a step" % [step]
            steps = []
            return false
        steps.append(step)
    return true


func _header_refusal(doc: Variant) -> String:
    if typeof(doc) != TYPE_DICTIONARY:
        return "not a step document"
    if doc.get("format") != FORMAT:
        return "format: %s, expected \"%s\"" % [doc.get("format"), FORMAT]
    if doc.get("version") != float(VERSION):
        return "version: %s, this build reads %d" % [doc.get("version"), VERSION]
    if doc.get("units") != UNITS:
        return "units: %s, this version's plain numbers are %s" % [doc.get("units"), UNITS]
    if typeof(doc.get("steps")) != TYPE_ARRAY:
        return "steps: missing"
    if doc.size() != 4:
        return "fields other than format, version, units and steps: %s" % [doc.keys()]
    return ""
