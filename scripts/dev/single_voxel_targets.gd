extends RefCounted

# Target selection and aiming for probe_single_voxel.gd: terrain columns scanned over the game's
# own field and classed by shape, then aimed at the way player.gd aims (TerrainRaymarch from the
# eye) and turned into a cell with ActionFactories.make_fill_voxel / make_empty_voxel's formulas.

const SCAN_HALF := 1000.0     # columns scanned over [-SCAN_HALF, SCAN_HALF]^2 ...
const SCAN_STEP := 20.0       # ... at this pitch
const EYE       := 3.5        # aim camera distance from the aimed point (m)
const NEAR_ZERO := 0.02       # a neighbour centre this close to zero makes a near_zero target

const CLASSES := ["flat", "gentle", "slope", "steep", "ridge", "valley",
    "near_zero_fill", "near_zero_empty", "cave_ceiling", "cave_wall", "cave_floor", "overhang_roof"]

var pristine:  EditStore
var rng        := RandomNumberGenerator.new()
var per_class: int


func _init(p_per_class: int) -> void:
    per_class = p_per_class
    rng.seed  = 1337
    pristine  = EditStore.new()
    pristine.setup(EditStoreManager.ROOT_ORIGIN, EditStoreManager.ROOT_SIZE, EditStoreManager.BASE,
        EditStoreManager.AMP, EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


func _height(x: float, z: float) -> float:
    return EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


func scan() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var x := -SCAN_HALF
    while x <= SCAN_HALF:
        var z := -SCAN_HALF
        while z <= SCAN_HALF:
            var jx := x + rng.randf_range(-SCAN_STEP, SCAN_STEP) * 0.5
            var jz := z + rng.randf_range(-SCAN_STEP, SCAN_STEP) * 0.5
            var h  := _height(jx, jz)
            var gx := (_height(jx + 1.0, jz) - _height(jx - 1.0, jz)) * 0.5
            var gz := (_height(jx, jz + 1.0) - _height(jx, jz - 1.0)) * 0.5
            var ring := (_height(jx + 4.0, jz) + _height(jx - 4.0, jz)
                + _height(jx, jz + 4.0) + _height(jx, jz - 4.0)) * 0.25
            out.append({"p": Vector3(jx, h, jz), "slope": Vector2(gx, gz).length(), "ridge": h - ring})
            z += SCAN_STEP
        x += SCAN_STEP
    return out


func class_of(col: Dictionary) -> String:
    var s: float = col.slope
    var r: float = col.ridge
    if r > 0.4:
        return "ridge"
    if r < -0.4:
        return "valley"
    if s < 0.08:
        return "flat"
    if s < 0.35:
        return "gentle"
    if s < 1.0:
        return "slope"
    return "steep"


func classify(columns: Array[Dictionary]) -> Dictionary:
    var by := {}
    for cls in CLASSES:
        by[cls] = []
    for col in columns:
        by[class_of(col)].append(col)
    for cls in ["near_zero_fill", "near_zero_empty"]:
        by[cls] = _near_zero(columns, cls == "near_zero_fill")
    by["valley"] = _concave(columns)
    for cls in ["cave_ceiling", "cave_wall", "cave_floor"]:
        by[cls] = by["flat"] + by["gentle"]
    by["overhang_roof"] = by["steep"]
    for cls in by:
        by[cls] = _spread(by[cls])
    return by


# Columns whose aimed cell has a neighbour centre within 0.02 of zero, closest first.
func _near_zero(columns: Array[Dictionary], fill: bool) -> Array:
    var scored := []
    for col in columns:
        var hit := aim(pristine, eye_for(col.p), col.p)
        if not hit.hit:
            continue
        var cell := fill_cell(hit) if fill else empty_cell(hit)
        var m := min_neighbour_abs(pristine, cell)
        if m < NEAR_ZERO:
            scored.append([m, col])
    scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
    return scored.slice(0, per_class * 4).map(func(e: Array) -> Dictionary: return e[1])


# The terrain has few columns past the -0.4 m ridge threshold (none in the default scan), so valley
# targets are the most concave columns instead: the tail of the ridge metric, most concave first.
func _concave(columns: Array[Dictionary]) -> Array:
    var dips := columns.filter(func(col: Dictionary) -> bool: return col.ridge < 0.0)
    dips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ridge < b.ridge)
    if not dips.is_empty():
        print("# valley: most concave ridge metric %.3f m, %d-th %.3f m" % [dips[0].ridge,
            mini(per_class * 4, dips.size()), dips[mini(per_class * 4, dips.size()) - 1].ridge])
    return dips.slice(0, per_class * 4)


func _spread(list: Array) -> Array:
    if list.size() <= per_class:
        return list
    var out := []
    for i in per_class:
        out.append(list[int(float(i) * list.size() / per_class)])
    return out


func min_neighbour_abs(store: EditStore, cell: Vector3i) -> float:
    var m := INF
    for o in offsets():
        if o != Vector3i.ZERO:
            m = minf(m, absf(TerrainProbe.sdf(store, cell + o)))
    return m


func offsets() -> Array[Vector3i]:
    var out: Array[Vector3i] = []
    for z in range(-1, 2):
        for y in range(-1, 2):
            for x in range(-1, 2):
                out.append(Vector3i(x, y, z))
    return out


# --- aiming (player.gd _raymarch_terrain + ActionFactories.make_fill_voxel / make_empty_voxel) --

func eye_for(p: Vector3) -> Vector3:
    var n := TerrainRaymarch._normal(pristine, p)
    return p + (n + Vector3.UP).normalized() * EYE


func aim(store: EditStore, eye: Vector3, at: Vector3) -> Dictionary:
    return TerrainRaymarch.surface(store, eye, (at - eye).normalized(), 30.0, 0.2)


func fill_cell(aim: Dictionary) -> Vector3i:
    return Vector3i((aim.position + aim.normal * 0.5).floor())


func empty_cell(aim: Dictionary) -> Vector3i:
    return Vector3i((aim.position - aim.normal * VoxelConstants.SURFACE_NUDGE).floor())
