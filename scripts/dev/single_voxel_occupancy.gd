extends RefCounted

# Validates single_voxel_mesh_diff.gd's +y ray-parity occupancy against the field's own sign, on the
# same targets probe_single_voxel.gd measures (pristine terrain and dug hollows), before and after
# the edit, for both render modes. Parity is the basis of every volume figure in the
# Characterization section of https://github.com/rdeforest/voxel-mvp/issues/22.
# DC places its surface by QEF, not at the field's zero, so mismatch is expected within a small
# band of the surface; FAR counts only points at least that far from zero in field units.

const Probe    := preload("res://scripts/dev/single_voxel_probe.gd")
const Targets  := preload("res://scripts/dev/single_voxel_targets.gd")
const MeshDiff := preload("res://scripts/dev/single_voxel_mesh_diff.gd")
const Tsv      := preload("res://scripts/dev/single_voxel_tsv.gd")

const FAR     := 0.3        # |sdf| beyond which parity and sign must agree
const STRIDE  := 2          # check every STRIDE-th grid point per axis
const COLUMNS := ["cls", "scenario", "phase", "mode", "cell", "points", "mismatch", "far_points",
    "far_mismatch", "capped"]

var t:     Targets
var probe: Probe
var rows:  Array[Dictionary] = []


func _init(p_targets: Targets) -> void:
    t     = p_targets
    probe = Probe.new(t, 0)


func run(out_path: String) -> void:
    var picked: Dictionary = t.classify(t.scan())
    for cls: String in picked:
        for col: Dictionary in picked[cls]:
            for scenario: Dictionary in probe._scenarios(cls, col):
                if scenario.name in ["single_fill", "single_empty"]:
                    _check(cls, scenario)
    if out_path != "":
        Tsv.write(out_path, rows, COLUMNS)


func _check(cls: String, scenario: Dictionary) -> void:
    var store := t.pristine.duplicate()
    if scenario.prep != null:
        (scenario.prep as Callable).call(store)
    var step: Dictionary = scenario.steps[0]
    var aim := t.aim(store, step.eye, step.at)
    if not aim.hit:
        return
    var fill: bool = step.verb == "fill"
    var cell := t.fill_cell(aim) if fill else t.empty_cell(aim)
    var action := probe._make(step.verb, cell, store)
    var edits := probe._refusal(store, cell, step.verb, action) == ""
    for phase in ["before", "after"]:
        if phase == "after":
            if not edits:
                return
            action.execute()
        for dense in [false, true]:
            var row := _compare(store, MeshDiff.of(store, cell, step.eye, dense))
            row.merge({"cls": cls, "scenario": scenario.name, "phase": phase,
                "mode": "dense" if dense else "live", "cell": cell})
            rows.append(row)
            print(Tsv.line(row, COLUMNS))


func _compare(store: EditStore, md: RefCounted) -> Dictionary:
    var points       := 0
    var mismatch     := 0
    var far_points   := 0
    var far_mismatch := 0
    for k in range(0, md.n, STRIDE):
        for j in range(0, md.n, STRIDE):
            for i in range(0, md.n, STRIDE):
                var sdf := store.sample(md.point(i, j, k))
                var wrong := int(probe._solid(sdf) != (md.inside[i + j * md.n + k * md.n * md.n] == 1))
                points   += 1
                mismatch += wrong
                if absf(sdf) >= FAR:
                    far_points   += 1
                    far_mismatch += wrong
    return {"points": points, "mismatch": mismatch, "far_points": far_points,
        "far_mismatch": far_mismatch, "capped": md.capped}
