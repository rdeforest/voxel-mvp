extends RefCounted

# The measured edits for probe_single_voxel.gd: each scenario starts from a fresh copy of the
# pristine store, and each step aims, builds the real FillVoxelAction / EmptyVoxelAction, records
# the LP's intent, executes it, and diffs DcWorldPreview-equivalent meshes from before and after.

const MeshDiff := preload("res://scripts/dev/single_voxel_mesh_diff.gd")
const Targets  := preload("res://scripts/dev/single_voxel_targets.gd")
const Legacy   := preload("res://scripts/dev/single_voxel_legacy.gd")
const Tsv      := preload("res://scripts/dev/single_voxel_tsv.gd")

const CUBE_FULL   := 0.9        # target solid fraction that reads as a filled cube
const CUBE_SPILL  := 0.25       # ... with at most this much volume outside the target (m^3)
const SEEN_DV     := 0.02       # |dV| (m^3) below which a change is called invisible
const SEEN_SHIFT  := 0.05       # ... together with a surface shift under this (m)
const TOUCH_DV    := 0.01       # |dV| in a neighbour cell that counts as "surface moved over it"
const MATERIAL    := &"Stone"

var t:           Targets
var rows:        Array[Dictionary] = []
var census_rows: Array[Dictionary] = []
var census:      int


func _init(p_targets: Targets, p_census: int) -> void:
    t      = p_targets
    census = p_census


func run(out_path: String) -> void:
    var columns: Array[Dictionary] = t.scan()
    var picked: Dictionary = t.classify(columns)
    print("# classes: ", picked.keys().map(func(k: String) -> String: return "%s=%d" % [k, picked[k].size()]))
    _print_header()
    for cls: String in picked:
        for col: Dictionary in picked[cls]:
            for scenario in _scenarios(cls, col):
                _play(cls, scenario)
    _census(columns)
    _write_tsv(out_path)


# [{name, prep: Callable(EditStore) or null, steps: [{verb, eye, at}]}]
func _scenarios(cls: String, col: Dictionary) -> Array:
    var p: Vector3 = col.p
    if cls.begins_with("near_zero"):
        var verb := "fill" if cls == "near_zero_fill" else "empty"
        return [_scenario("single_" + verb, null, t.eye_for(p), p, [verb], Vector3.ZERO)]
    if cls.begins_with("cave") or cls == "overhang_roof":
        return _hollow_scenarios(cls, p)
    var eye := t.eye_for(p)
    return [
        _scenario("single_fill",     null, eye, p, ["fill"],                  Vector3.ZERO),
        _scenario("single_empty",    null, eye, p, ["empty"],                 Vector3.ZERO),
        _scenario("legacy_fill",     null, eye, p, ["legacy_fill"],           Vector3.ZERO),
        _scenario("legacy_empty",    null, eye, p, ["legacy_empty"],          Vector3.ZERO),
        _scenario("repeat_fill",     null, eye, p, ["fill", "fill", "fill"],  Vector3.ZERO),
        _scenario("repeat_empty",    null, eye, p, ["empty", "empty", "empty"], Vector3.ZERO),
        _scenario("fill_then_empty", null, eye, p, ["fill", "empty"],         Vector3.ZERO),
        _scenario("adjacent_fill",   null, eye, p, ["fill", "fill", "fill"],  Vector3.RIGHT),
        _scenario("adjacent_empty",  null, eye, p, ["empty", "empty", "empty"], Vector3.RIGHT),
    ]


# A dug hollow (DigAction, the in-game carve) with the eye inside it, aimed at a hollow face. A cave
# is a sphere buried under the column; an overhang is a sphere dug sideways into a steep face, so
# the hill above it is its roof.
func _hollow_scenarios(cls: String, p: Vector3) -> Array:
    var n      := TerrainRaymarch._normal(t.pristine, p)
    var inward := -Vector3(n.x, 0.0, n.z).normalized()
    var centre := p - Vector3.UP * 5.0
    var radius := 3.0
    var look   := {"cave_ceiling": Vector3.UP, "cave_wall": Vector3.RIGHT, "cave_floor": Vector3.DOWN,
        "overhang_roof": Vector3.UP}[cls] as Vector3
    if cls == "overhang_roof":
        centre = p + inward * 3.0 - Vector3.UP
        radius = 2.5
    var prep := func(store: EditStore) -> void:
        DigAction.new(centre, radius, ActionContext.new(store, null, null)).execute()
    var at := centre + look * 10.0
    return [
        _scenario("single_fill",     prep, centre, at, ["fill"],          Vector3.ZERO),
        _scenario("single_empty",    prep, centre, at, ["empty"],         Vector3.ZERO),
        _scenario("repeat_fill",     prep, centre, at, ["fill", "fill"],  Vector3.ZERO),
        _scenario("fill_then_empty", prep, centre, at, ["fill", "empty"], Vector3.ZERO),
    ]


func _scenario(name: String, prep: Variant, eye: Vector3, at: Vector3, verbs: Array, stride: Vector3) -> Dictionary:
    var steps := []
    for i in verbs.size():
        steps.append({"verb": verbs[i], "eye": eye + stride * i, "at": at + stride * i})
    return {"name": name, "prep": prep, "steps": steps}


func _play(cls: String, scenario: Dictionary) -> void:
    var store := t.pristine.duplicate()
    if scenario.prep != null:
        (scenario.prep as Callable).call(store)
    for i in scenario.steps.size():
        var step: Dictionary = scenario.steps[i]
        var row := {"cls": cls, "scenario": scenario.name, "step": i, "verb": step.verb}
        _edit(store, step, row)
        rows.append(row)
        print(Tsv.line(row, COLUMNS))


# --- one edit, measured ------------------------------------------------------------------------

func _edit(store: EditStore, step: Dictionary, row: Dictionary) -> void:
    if _solid(store.sample(step.eye)):
        row.refused = "eye_in_solid"
        return
    var aim := t.aim(store, step.eye, step.at)
    if not aim.hit:
        row.refused = "no_hit"
        return
    var verb: String = step.verb
    var cell := t.fill_cell(aim) if verb.ends_with("fill") else t.empty_cell(aim)
    var action := _make(verb, cell, store)
    row.cell     = cell
    row.normal   = aim.normal
    row.aim_off  = aim.position - VoxelUtils.sample_point(cell)
    row.refused  = _refusal(store, cell, verb, action)
    row.nb_min   = t.min_neighbour_abs(store, cell)
    if row.refused != "":
        return
    _intent(store, cell, action._work(), row)
    var centres := _centres(store, cell)
    var corner  := store.sample(Vector3(cell))
    var live    := MeshDiff.of(store, cell, step.eye, false)
    var dense   := MeshDiff.of(store, cell, step.eye, true)
    action.execute()
    _flips(store, cell, centres, corner, row)
    _geometry(cell, live,  MeshDiff.of(store, cell, step.eye, false), row, "live_")
    _geometry(cell, dense, MeshDiff.of(store, cell, step.eye, true),  row, "dense_")


# The edit a verb makes at `cell`: the live action, or its pre-f11d284 rule (single_voxel_legacy.gd).
func _make(verb: String, cell: Vector3i, store: EditStore) -> Object:
    var ctx := ActionContext.new(store, null, null)
    var stone := MaterialPalette.index_of(MATERIAL)
    return {
        "fill":         func() -> Object: return FillVoxelAction.new(cell, ctx, MATERIAL),
        "empty":        func() -> Object: return EmptyVoxelAction.new(cell, ctx),
        "legacy_fill":  func() -> Object: return Legacy.new(cell, store, true, stone),
        "legacy_empty": func() -> Object: return Legacy.new(cell, store, false, -1),
    }[verb].call()


func _refusal(store: EditStore, cell: Vector3i, verb: String, action: Object) -> String:
    if action is Legacy:
        return action.refusal()
    var fill := verb == "fill"
    if TerrainProbe.is_solid(store, cell) == fill:
        return "already_solid" if fill else "already_air"
    return "" if action.validate() else "lp_infeasible"


# What the LP asked for: each corner push (offset from the target's min corner, and the change),
# the centres they predict for the target and its 26 neighbours, and the tightest neighbour margin.
func _intent(store: EditStore, cell: Vector3i, work: Array[LatticeEdit], row: Dictionary) -> void:
    var push       := 0.0
    var sign_flips := 0
    var corners    := PackedStringArray()
    for edit in work:
        var was := store.sample(Vector3(edit.point))
        push = maxf(push, absf(edit.sdf - was))
        corners.append("%d,%d,%d:%.3f" % [edit.point.x - cell.x, edit.point.y - cell.y,
            edit.point.z - cell.z, edit.sdf - was])
        if _solid(was) != _solid(edit.sdf):
            sign_flips += 1
    var lat    := StoreWrite.lattice(store, work)
    var margin := INF
    var nb     := PackedStringArray()
    for o in _neighbours():
        var at := VoxelUtils.sample_point(cell + o)
        if not _covers(lat, at):
            nb.append("")
            continue
        margin = minf(margin, absf(lat.value_at(at)))
        nb.append("%.4f" % lat.value_at(at))
    row.push         = push
    row.corner_flips = sign_flips
    row.corners      = ";".join(corners)
    row.centre_was   = TerrainProbe.sdf(store, cell)
    row.centre_pred  = lat.value_at(VoxelUtils.sample_point(cell))
    row.nb_margin    = margin
    row.nb_pred      = ";".join(nb)


func _neighbours() -> Array[Vector3i]:
    return t.offsets().filter(func(o: Vector3i) -> bool: return o != Vector3i.ZERO)


# The legacy one-point write's lattice spans only the target's corners +- 1, not its neighbours' centres.
func _covers(lat: SdfLattice, p: Vector3) -> bool:
    var far := lat.origin + Vector3.ONE * float(lat.dim - 1) * lat.cell
    return p.x >= lat.origin.x and p.y >= lat.origin.y and p.z >= lat.origin.z \
        and p.x < far.x and p.y < far.y and p.z < far.z


func _centres(store: EditStore, cell: Vector3i) -> Dictionary:
    var out := {}
    for z in range(-2, 3):
        for y in range(-2, 3):
            for x in range(-2, 3):
                var c := cell + Vector3i(x, y, z)
                out[c] = TerrainProbe.sdf(store, c)
    return out


# Centre sign flips after the edit (target, and any other cell in the 5x5x5), the neighbours'
# measured centres to set against the LP's prediction, and whether the target's min corner flipped:
# the lattice point the pre-f11d284 rule was aiming to flip.
func _flips(store: EditStore, cell: Vector3i, before: Dictionary, corner_was: float, row: Dictionary) -> void:
    var others := 0
    for c: Vector3i in before:
        if c != cell and _solid(before[c]) != TerrainProbe.is_solid(store, c):
            others += 1
    var nb := PackedStringArray()
    for o in _neighbours():
        nb.append("%.4f" % TerrainProbe.sdf(store, cell + o))
    row.centre_now   = TerrainProbe.sdf(store, cell)
    row.nb_now       = ";".join(nb)
    row.other_flips  = others
    row.target_flip  = _solid(before[cell]) != TerrainProbe.is_solid(store, cell)
    row.corner_flip  = _solid(corner_was) != _solid(store.sample(Vector3(cell)))


# TerrainProbe.is_solid's predicate, for raw values already sampled.
func _solid(sdf: float) -> bool:
    return sdf < VoxelConstants.SDF_SOLID_THRESHOLD


func _geometry(cell: Vector3i, before: RefCounted, after: RefCounted, row: Dictionary, pre: String) -> void:
    var vc: Dictionary = after.volume_change(before)
    var total: float   = vc.added + vc.removed
    var own: float     = vc.by_cell.get(cell, 0.0)
    var touched := 0
    for c: Vector3i in vc.by_cell:
        if c != cell and vc.by_cell[c] >= TOUCH_DV:
            touched += 1
    var shift: Vector2 = after.surface_shift(before)
    row[pre + "added"]     = vc.added
    row[pre + "removed"]   = vc.removed
    row[pre + "own"]       = own
    row[pre + "spill"]     = total - own
    row[pre + "frac_was"]  = before.solid_fraction(cell)
    row[pre + "frac_now"]  = after.solid_fraction(cell)
    row[pre + "extent"]    = vc.extent.size
    row[pre + "shift"]     = shift.x
    row[pre + "topo"]      = int(shift.y)
    row[pre + "touched"]   = touched
    row[pre + "moved"]     = after.moved_vertices(before).size()
    row[pre + "moved_far"] = after.moved_far_vertices(before)
    row[pre + "capped"]    = maxi(before.capped, after.capped)
    _centroid(cell, vc, row, pre)
    row[pre + "shape"]     = _shape(row, pre)
    _paint(cell, before, after, row, pre)


# Where the change sits: distance from the target centre, and its offset along the aim normal
# measured from the target centre and from the aimed hit point (> 0 = air side).
func _centroid(cell: Vector3i, vc: Dictionary, row: Dictionary, pre: String) -> void:
    if vc.added + vc.removed <= 0.0:
        row[pre + "centroid"] = -1.0
        return
    var off: Vector3 = vc.centroid - VoxelUtils.sample_point(cell)
    row[pre + "centroid"]       = off.length()
    row[pre + "centroid_n"]     = off.dot(row.normal)
    row[pre + "centroid_hit_n"] = (off - row.aim_off).dot(row.normal)


func _shape(row: Dictionary, pre: String) -> String:
    var fill: bool = row.verb.ends_with("fill")
    var frac: float = row[pre + "frac_now"]
    var full := frac >= CUBE_FULL if fill else frac <= 1.0 - CUBE_FULL
    if full and row[pre + "spill"] <= CUBE_SPILL:
        return "cube"
    if absf(row[pre + "added"] - row[pre + "removed"]) < SEEN_DV and row[pre + "shift"] < SEEN_SHIFT:
        return "invisible"
    return "bump" if fill else "dent"


# Where explicit-material vertex colour landed: new painted vertices in / outside the target cell,
# and how many moved vertices carry it.
func _paint(cell: Vector3i, before: RefCounted, after: RefCounted, row: Dictionary, pre: String) -> void:
    var was := {}
    for i in before.verts.size():
        if before.colors[i].a < 0.5:
            was[Vector3i((before.verts[i] / MeshDiff.SAME_VERT).round())] = true
    var moved := {}
    for p in after.moved_vertices(before):
        moved[p] = true
    var inside  := 0
    var outside := 0
    var moved_painted := 0
    for i in after.verts.size():
        var p: Vector3 = after.verts[i]
        if after.colors[i].a >= 0.5:
            continue
        moved_painted += 1 if moved.has(p) else 0
        if was.has(Vector3i((p / MeshDiff.SAME_VERT).round())):
            continue
        if Vector3i(p.floor()) == cell:
            inside += 1
        else:
            outside += 1
    row[pre + "paint_in"]    = inside
    row[pre + "paint_out"]   = outside
    row[pre + "paint_moved"] = moved_painted


# --- census: validate() + LP intent only, over many aimed targets --------------------------------

func _census(columns: Array[Dictionary]) -> void:
    for i in mini(census, columns.size()):
        var col: Dictionary = columns[t.rng.randi_range(0, columns.size() - 1)]
        var aim := t.aim(t.pristine, t.eye_for(col.p), col.p)
        if not aim.hit:
            continue
        for verb: String in ["fill", "empty", "legacy_fill", "legacy_empty"]:
            var cell   := t.fill_cell(aim) if verb.ends_with("fill") else t.empty_cell(aim)
            var action := _make(verb, cell, t.pristine)
            var row    := {"cls": t.class_of(col), "verb": verb, "cell": cell,
                "refused": _refusal(t.pristine, cell, verb, action)}
            if row.refused == "" and not verb.begins_with("legacy"):
                _intent(t.pristine, cell, action._work(), row)
            census_rows.append(row)


# --- output ------------------------------------------------------------------------------------

const COLUMNS := ["cls", "scenario", "step", "verb", "cell", "normal", "aim_off", "refused", "nb_min",
    "push", "corner_flips", "corners", "centre_was", "centre_pred", "centre_now", "nb_margin", "nb_pred", "nb_now",
    "target_flip", "corner_flip", "other_flips",
    "live_added", "live_removed", "live_own", "live_spill", "live_frac_was", "live_frac_now", "live_centroid",
    "live_centroid_n", "live_centroid_hit_n", "live_extent", "live_shift", "live_topo", "live_touched", "live_moved",
    "live_moved_far", "live_capped", "live_shape", "live_paint_in", "live_paint_out", "live_paint_moved",
    "dense_added", "dense_removed", "dense_own", "dense_spill", "dense_frac_now", "dense_centroid_hit_n",
    "dense_shift", "dense_topo", "dense_touched", "dense_moved_far", "dense_capped", "dense_shape"]

const CENSUS_COLUMNS := ["cls", "verb", "cell", "refused", "push", "corner_flips"]


func _print_header() -> void:
    print("\t".join(COLUMNS))


# The edit rows go to `out_path`, the census rows beside it as <name>.census.tsv.
func _write_tsv(out_path: String) -> void:
    if out_path == "":
        return
    Tsv.write(out_path, rows, COLUMNS)
    Tsv.write(out_path.get_basename() + ".census.tsv", census_rows, CENSUS_COLUMNS)
