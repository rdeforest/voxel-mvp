extends GutTest

# Where does the DC world mesher spend its refinement budget and its triangles, and how wrong is
# the mesh where the eye goes? Evidence for docs/roadmap/reference/09-perceptual-lod-research.md.
# Measures only; changes nothing.
#
# Scene: the live EditStoreManager field, a flat camera site with a sharp generator ridge ~100 m
# away, and a "mini-stonehenge" of axis-aligned stone boxes 8-20 m in front of the camera, imprinted
# through the construction write path (EditStore.predict_imprint -> SdfLattice.write, what
# VoxelImprint.apply does minus its events). Every box's MIN corner sits PHASE past a lattice plane
# on each axis; its max faces land wherever its size puts them. Driven through the calls
# DcWorldPreview makes, with its constants (DEPTH 13, 128 m drawn, 256 m retained, EPS_START 48,
# x0.9 per job, EPS_MIN 0.5). The refine budget is a fixed POP count, not wall-clock, so every
# number here reproduces run to run.
#
# Run (scratch log via tee):
#   godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/dev/probe_perceptual_lod.gd \
#       -gunit_test_name=test_stones      (or test_steady_state / test_bloom_drawn / test_bloom_frontier)

const DEPTH      := 13
const ROOT_SIZE  := 1 << DEPTH
const ROOT_SNAP  := 64
const WIN_R      := 128
const RETAIN_R   := 256
const EPS_START  := 48.0
const EPS_MIN    := 0.5
const VP_H       := 1080.0
const FOV_DEG    := 75.0
const ASPECT     := 16.0 / 9.0
const EYE_H      := 1.7
const SITE       := Vector2(224.0, -384.0)
const CREST      := Vector2(320.0, -344.0)
const STONES_AT  := 14.0
const PHASE_MAIN := 0.25
const PHASES     := [0.0, 0.1, 0.25, 0.5, 0.75]
const SINK       := 0.2
const STONE_LIFT := 0.3
const EDIT_PAD   := 1.0
const RIDGE_R    := 25.0
const FEATURE_DEG := 20.0
const BANDS      := [20.0, 40.0, 60.0, 90.0, 130.0, 1e9]
const ERR_STRIDE := 7
const POPS_PER_JOB := 256
const POP_TRACE  := 400
const DRAIN_MARKS := [0, 25, 100]
const FRONTIER_DRAIN_MARKS := [0, 25]
const MID_EPS    := 8.0
const SUB_CELL   := 0.25
const SUB_WIN_R  := 32
const RAY_REACH  := 3.0
const NEAR_CAP   := 0.5
const HASH_H     := 0.5

var store:  EditStore
var gen:    EditStore
var proj    := VP_H / (2.0 * tan(deg_to_rad(FOV_DEG) * 0.5))
var root_o  := Vector3i.ZERO
var eye     := Vector3.ZERO
var cam_l   := Vector3.ZERO
var fwd     := Vector3.ZERO
var right   := Vector3.ZERO
var up      := Vector3.ZERO
var blocks: Array = []
var palette: PackedColorArray
var stone   := 0
var bc      := 1.0
var stamp_leaf := 1.0
var phase   := PHASE_MAIN
var ground_cache := {}


# Four independent tests (each stages its own scene), so they can run as parallel processes with
# -gunit_test_name=<name>. Every number is deterministic: a rerun reproduces it exactly.

func test_steady_state() -> void:
    _setup_scene()
    _report_scene()
    _imprint_equivalence()
    _steady_state_section()
    assert_true(true, "probe ran")


func test_bloom_drawn() -> void:
    _setup_scene()
    _bloom_section(true, DRAIN_MARKS)
    assert_true(true, "probe ran")


func test_bloom_frontier() -> void:
    _setup_scene()
    _bloom_section(false, FRONTIER_DRAIN_MARKS)
    assert_true(true, "probe ran")


func test_stones() -> void:
    _setup_scene()
    _phase_sweep_section()
    _subdiv_section(SUB_CELL, 1.0, PHASE_MAIN)
    _subdiv_section(1.0, SUB_CELL, PHASE_MAIN)
    assert_true(true, "probe ran")


# --- scene ------------------------------------------------------------------------------------------

func _surface_y(s: EditStore, x: float, z: float) -> float:
    var lo := -400.0
    var hi := 400.0
    for _i in 44:
        var mid := (lo + hi) * 0.5
        if s.sample(Vector3(x, mid, z)) < 0.0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) * 0.5


# Generator ground height (no stones), cached on a 0.25 m grid.
func _ground_y(x: float, z: float) -> float:
    var k := Vector2i(roundi(x * 4.0), roundi(z * 4.0))
    if not ground_cache.has(k):
        ground_cache[k] = _surface_y(gen, k.x * 0.25, k.y * 0.25)
    return ground_cache[k]


func _new_store() -> EditStore:
    var mgr := EditStoreManager.new()
    mgr.setup()
    return mgr.store


func _setup_scene() -> void:
    gen = _new_store()
    palette = MaterialPalette.colors()
    stone = MaterialPalette.index_of(&"Stone")
    var ground := _surface_y(gen, SITE.x, SITE.y)
    eye = Vector3(SITE.x, ground + EYE_H, SITE.y)
    var crest := Vector3(CREST.x, _surface_y(gen, CREST.x, CREST.y), CREST.y)
    fwd = (crest - eye).normalized()
    right = fwd.cross(Vector3.UP).normalized()
    up = right.cross(fwd)
    _restage(1.0, 1.0, PHASE_MAIN)


# A fresh store with the stones imprinted at `leaf`, meshed at base cell `cell`.
func _restage(cell: float, leaf: float, p_phase: float, use_stamp := false) -> void:
    bc = cell
    stamp_leaf = leaf
    phase = p_phase
    store = _new_store()
    blocks = []
    var flat_dir := Vector3(fwd.x, 0.0, fwd.z).normalized()
    _place_stonehenge(Vector3(eye.x, 0.0, eye.z) + flat_dir * STONES_AT, use_stamp)
    _set_lattice()


# Root + camera in the octree lattice at the current base cell (DcWorldPreview._snap_root).
func _set_lattice() -> void:
    var o := ((eye / bc - Vector3.ONE * (ROOT_SIZE * 0.5)) / ROOT_SNAP).floor() * ROOT_SNAP
    root_o = Vector3i(o)
    cam_l = eye / bc - Vector3(root_o)


# The largest value <= v whose fractional part is `phase`.
func _snap(v: float) -> float:
    return floorf(v - phase) + phase


# Three trilithons (two uprights + a lintel spanning them) on a 5 m ring, plus a fallen block lying
# half sunk. Every min corner is snapped to `phase`.
func _place_stonehenge(c: Vector3, use_stamp: bool) -> void:
    _trilithon(c + Vector3(-5, 0, 0), Vector3(1.0, 4.0, 1.5), Vector3(0, 0, 1.5), Vector3(1.0, 1.0, 4.5), use_stamp)
    _trilithon(c + Vector3(0, 0, -5), Vector3(1.5, 4.0, 1.0), Vector3(1.5, 0, 0), Vector3(4.5, 1.0, 1.0), use_stamp)
    _trilithon(c + Vector3(5, 0, 0), Vector3(1.0, 4.0, 1.5), Vector3(0, 0, 1.5), Vector3(1.0, 1.0, 4.5), use_stamp)
    var fp := c + Vector3(0, 0, 4)
    var y0 := _snap(_ground_y(fp.x, fp.z) - STONE_LIFT)
    _box(Vector3(_snap(fp.x), y0, _snap(fp.z)), Vector3(3.5, 1.5, 1.0), use_stamp)


func _trilithon(at: Vector3, upright: Vector3, offset: Vector3, lintel: Vector3, use_stamp: bool) -> void:
    var a := at - offset
    var b := at + offset
    var y0 := _snap(maxf(_ground_y(a.x, a.z), _ground_y(b.x, b.z)) - SINK)
    for p in [a, b]:
        _box(Vector3(_snap(p.x), y0, _snap(p.z)), upright, use_stamp)
    _box(Vector3(_snap(a.x), y0 + upright.y, _snap(a.z)), lintel, use_stamp)


# Imprint one box whose min corner is `lo`: the construction write (predict_imprint -> write with
# the lattice's own materials), or the older EditStore.stamp_box for the equivalence check.
func _box(lo: Vector3, size: Vector3, use_stamp: bool) -> void:
    var center := lo + size * 0.5
    blocks.append(AABB(lo, size))
    if use_stamp:
        store.stamp_box(center, size, VoxelConstants.STORE_OP_UNION, stone, stamp_leaf)
        return
    var lat := SdfLattice.predicted(store.predict_imprint(CsgSdf.Shape.BOX,
            PackedFloat64Array([size.x, size.y, size.z]), Transform3D(Basis(), center), CsgState.Op.ADD, stamp_leaf))
    lat.write(store, lat.materials(store, stone, false))


func _stones_region() -> AABB:
    var region := AABB(blocks[0].position, Vector3.ZERO)
    for b in blocks:
        region = region.merge(b)
    return region


func _report_scene() -> void:
    gut.p("R1 SCENE  eye %s  crest %s (%.0f m)  proj %.1f px/unit (vp %d, fov %d, %.2f aspect)" % [
            eye, Vector2(CREST.x, CREST.y), Vector2(eye.x, eye.z).distance_to(CREST), proj, VP_H, FOV_DEG, ASPECT])
    gut.p("R1 SCENE  root %s  phase %.2f  blocks %d:" % [root_o, phase, blocks.size()])
    for b in blocks:
        gut.p("  block %s size %s  dist %.1f m" % [b.position, b.size, (b.get_center() - eye).length()])
    var hfov := 2.0 * rad_to_deg(atan(tan(deg_to_rad(FOV_DEG) * 0.5) * ASPECT))
    var inside := 0
    var total := 0
    var gy := eye.y - EYE_H
    for x in range(-WIN_R, WIN_R):
        for z in range(-WIN_R, WIN_R):
            total += 1
            inside += 1 if _in_frustum(Vector3(eye.x + x + 0.5, gy, eye.z + z + 0.5)) else 0
    gut.p("R1 SCENE  horizontal fov %.1f deg; geometric baseline: %.1f%% of a flat plane at ground height over the +-%d m window is outside the frustum" % [
            hfov, 100.0 - 100.0 * inside / total, WIN_R])


# Construction path vs EditStore.stamp_box, and both vs the analytic field min(generator, boxes), at
# every lattice corner around the stones.
func _imprint_equivalence() -> void:
    var imprint := store
    var imprint_blocks := blocks
    _restage(bc, stamp_leaf, phase, true)
    var stamped := store
    store = imprint
    blocks = imprint_blocks
    var box := _stones_region().grow(3.0)
    var lo := Vector3i((box.position / bc).floor())
    var hi := Vector3i((box.end / bc).ceil())
    var n := 0
    var n_edge := 0
    var diff := 0.0
    var diff_edge := 0.0
    var sign_diff := 0
    var vs_true := 0.0
    for x in range(lo.x, hi.x + 1):
        for y in range(lo.y, hi.y + 1):
            for z in range(lo.z, hi.z + 1):
                var p := Vector3(x, y, z) * bc
                var a := imprint.sample(p)
                var b := stamped.sample(p)
                n += 1
                diff = maxf(diff, absf(a - b))
                sign_diff += 1 if (a < 0.0) != (b < 0.0) else 0
                if not (_on_crossing_edge(imprint, p) or _on_crossing_edge(stamped, p)):
                    continue
                n_edge += 1
                diff_edge = maxf(diff_edge, absf(a - b))
                vs_true = maxf(vs_true, absf(a - minf(gen.sample(p), _box_union(p))))
    gut.p("R1 IMPRINT  corners %d: sign mismatches construction imprint vs stamp_box %d; |difference| max %.4f over all corners, %.4f over the %d corners on a sign-changing lattice edge (what the mesher reads); construction imprint vs min(generator, analytic boxes) on those corners max %.4f" % [
            n, sign_diff, diff, diff_edge, n_edge, vs_true])


func _on_crossing_edge(s: EditStore, p: Vector3) -> bool:
    var inside := s.sample(p) < 0.0
    for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
        if (s.sample(p + d * bc) < 0.0) != inside:
            return true
    return false


# --- windows + calls (DcWorldPreview's own) ---------------------------------------------------------

func _window(r_m: int) -> Array:
    var r := int(ceil(r_m / bc))
    var c := Vector3i((eye / bc).round())
    return [(c - Vector3i.ONE * r).clamp(root_o, root_o + Vector3i.ONE * ROOT_SIZE),
            (c + Vector3i.ONE * r).clamp(root_o, root_o + Vector3i.ONE * ROOT_SIZE)]


func _new_mesher() -> DCOctreeMesher:
    var m := DCOctreeMesher.new()
    m.set_thread_count(mini(OS.get_processor_count(), 8))
    return m


func _build(m: DCOctreeMesher, eps: float, collapse: bool, r_m := WIN_R) -> Array:
    var vis := _window(r_m)
    return m.mesh_world(store, root_o, DEPTH, bc, cam_l, proj, eps, collapse, palette, vis[0], vis[1], 80_000_000)


func _grow(m: DCOctreeMesher, eps: float, budget: int, reuse: bool, emit_r := WIN_R) -> Array:
    var ret := _window(RETAIN_R)
    var vis := _window(emit_r)
    return m.grow_world(cam_l, proj, eps, ret[0], ret[1], budget, vis[0], vis[1], reuse)


# `pops` candidates exactly: budget 0 refines one per grow (refine_selected pops before it checks the
# clock). The first grow rebuilds the frontier when `rebuild` (an eps change), the rest drain it.
func _grow_pops(m: DCOctreeMesher, eps: float, pops: int, rebuild: bool, emit_r: int) -> Array:
    var arrays := _grow(m, eps, 0, not rebuild, emit_r)
    for _i in pops - 1:
        if not m.get_refine_pending():
            break
        arrays = _grow(m, eps, 0, true, emit_r)
    return arrays


# --- per-triangle geometry --------------------------------------------------------------------------

# Triangle owners are WORLD lattice (cell_world_origin); x bc = world metres. The graded floor is
# clamp(eps/proj * d, 1 lattice unit).
func _floor_at(center_w: Vector3, eps: float) -> float:
    return clampf(eps / proj * (center_w - eye).length(), bc, 1e9)


func _owner_is_edit(o_w: Vector3, size: float) -> bool:
    var box := AABB(o_w, Vector3.ONE * size)
    for b in blocks:
        if box.intersects(b.grow(EDIT_PAD)):
            return true
    return false


func _band(d: float) -> String:
    var lo := 0.0
    for hi in BANDS:
        if d < hi:
            return "%3d-%s" % [lo, "inf" if hi > 1e8 else "%d" % hi]
        lo = hi
    return "?"


func _in_frustum(p_world: Vector3) -> bool:
    var v := p_world - eye
    var z := v.dot(fwd)
    if z <= 0.0:
        return false
    var tv := tan(deg_to_rad(FOV_DEG) * 0.5)
    return absf(v.dot(up)) <= z * tv and absf(v.dot(right)) <= z * tv * ASPECT


# Projected screen area in px² of a triangle wholly in front of the eye; -1 when any vertex is not.
func _screen_area(a: Vector3, b: Vector3, c: Vector3) -> float:
    var s := []
    for p in [a, b, c]:
        var v: Vector3 = p - eye
        var z := v.dot(fwd)
        if z < 0.05:
            return -1.0
        s.append(Vector2(v.dot(right), v.dot(up)) * proj / z)
    var e1: Vector2 = s[1] - s[0]
    var e2: Vector2 = s[2] - s[0]
    return absf(e1.cross(e2)) * 0.5


func _in_box(p: Vector3, win: Array) -> bool:
    return AABB(Vector3(win[0]) * bc, Vector3(win[1] - win[0]) * bc).has_point(p)


func _cand_region(c: Cand) -> String:
    var r := "EDIT" if c.edit else ("RIDGE" if c.ridge else "gen %s %s" % [_band(c.d), "feat" if c.spread >= FEATURE_DEG else "smth"])
    return r if c.drawn else r + " (undrawn ring)"


func _near_crest(p_world: Vector3) -> bool:
    return Vector2(p_world.x, p_world.z).distance_to(CREST) < RIDGE_R


# First-order distance to the stored field's zero set: |f| / |grad f| (the store SDF is not
# unit-distance on generator slopes, so raw |f| would misreport).
func _field_dist(s: EditStore, p: Vector3) -> float:
    return absf(s.sample(p)) / maxf(_grad_raw(s, p, 0.05).length(), 1e-6)


# Mesh-to-field error of one triangle: max over centroid + edge midpoints (vertices are QEF
# solutions and near-zero by construction, so the interior is where a coarse facet strays).
func _tri_field_err(a: Vector3, b: Vector3, c: Vector3) -> float:
    var e := _field_dist(store, (a + b + c) / 3.0)
    for p in [(a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5]:
        e = maxf(e, _field_dist(store, p))
    return e


func _normal_spread_deg(n: PackedVector3Array, ia: int, ib: int, ic: int) -> float:
    var m := minf(n[ia].dot(n[ib]), minf(n[ib].dot(n[ic]), n[ic].dot(n[ia])))
    return rad_to_deg(acos(clampf(m, -1.0, 1.0)))


# --- analytic intent ---------------------------------------------------------------------------------

func _box_sdf(p: Vector3, b: AABB) -> float:
    return CsgSdf.box(p - b.get_center(), b.size)


func _box_union(p: Vector3) -> float:
    var d := 1e9
    for b in blocks:
        d = minf(d, _box_sdf(p, b))
    return d


func _box_union_grad(p: Vector3) -> Vector3:
    const H := 1e-4
    return Vector3(_box_union(p + Vector3(H, 0, 0)) - _box_union(p - Vector3(H, 0, 0)),
            _box_union(p + Vector3(0, H, 0)) - _box_union(p - Vector3(0, H, 0)),
            _box_union(p + Vector3(0, 0, H)) - _box_union(p - Vector3(0, 0, H))).normalized()


# Signed first-order distance to the generator surface (no stones).
func _gen_sdist(p: Vector3) -> float:
    return gen.sample(p) / maxf(_grad_raw(gen, p, 0.05).length(), 1e-6)


# The player's intent: min(generator ground, analytic boxes), as a signed distance.
func _intent_sdist(p: Vector3) -> float:
    return minf(_gen_sdist(p), _box_union(p))


# --- aggregation ------------------------------------------------------------------------------------

class Agg:
    var n := 0
    var size_sum := 0.0
    var size_max := 0.0
    var key_sum := 0.0
    var flag_floor := 0
    var flag_cand := 0
    var in_view := 0
    var px_n := 0
    var px_area := 0.0
    var err_px: PackedFloat32Array = []
    var err_m: PackedFloat32Array = []

    func pctl(a: PackedFloat32Array, q: float) -> float:
        if a.is_empty():
            return NAN
        var s := a.duplicate()
        s.sort()
        return s[mini(int(q * s.size()), s.size() - 1)]


func _agg(d: Dictionary, k: String) -> Agg:
    if not d.has(k):
        d[k] = Agg.new()
    return d[k]


func _edit_region(a: Vector3, b: Vector3, c: Vector3) -> String:
    var ctr := (a + b + c) / 3.0
    return "EDIT stone" if ctr.y - _ground_y(ctr.x, ctr.z) >= STONE_LIFT else "EDIT apron"


# Walk an emitted mesh: bucket each live triangle by region and accumulate owner size, screen key,
# the dcinval flag (split by whether the owner is at its graded floor or above it), projected screen
# area (in view only), and (strided outside the edits) measured field error.
func _tri_table(arrays: Array, m: DCOctreeMesher, eps: float) -> Dictionary:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
    var owners := m.get_last_triangle_owners()
    var sizes := m.get_last_triangle_owner_sizes()
    var errs := m.get_last_triangle_owner_errors()
    var ro := Vector3(root_o)
    var out := {}
    for t in owners.size():
        var ia := idx[t * 3]
        var ib := idx[t * 3 + 1]
        var ic := idx[t * 3 + 2]
        if ia == ib or ib == ic or ia == ic:
            continue
        var a := (verts[ia] + ro) * bc
        var b := (verts[ib] + ro) * bc
        var c := (verts[ic] + ro) * bc
        var size := sizes[t] * bc
        var ctr_owner := (owners[t] + Vector3.ONE * (sizes[t] * 0.5)) * bc
        var d := maxf((ctr_owner - eye).length(), 1e-3)
        var edit := _owner_is_edit(owners[t] * bc, size)
        var spread := _normal_spread_deg(norms, ia, ib, ic)
        var region := _edit_region(a, b, c) if edit else ("gen %s %s" % [_band(d), "feat" if spread >= FEATURE_DEG else "smth"])
        var keys := [region, "ALL"]
        if edit:
            keys.append("EDIT all")
        elif d >= 60.0 and _near_crest((a + b + c) / 3.0):
            keys.append("RIDGE(crest disk)")
        var key := errs[t] * bc * proj / d
        var flagged := key > eps * 2.0
        var above_floor := size > _floor_at(ctr_owner, eps) + 1e-6
        var measure := edit or t % ERR_STRIDE == 0
        var e := _tri_field_err(a, b, c) if measure else 0.0
        var vis := _in_frustum((a + b + c) / 3.0)
        var px := _screen_area(a, b, c) if vis else -1.0
        for k in keys:
            var g := _agg(out, k)
            g.n += 1
            g.size_sum += size
            g.size_max = maxf(g.size_max, size)
            g.key_sum += key
            g.flag_floor += 1 if flagged and not above_floor else 0
            g.flag_cand += 1 if flagged and above_floor else 0
            g.in_view += 1 if vis else 0
            if px >= 0.0:
                g.px_n += 1
                g.px_area += px
            if measure:
                g.err_m.append(e)
                g.err_px.append(e * proj / d)
    return out


func _print_tri_table(title: String, t: Dictionary) -> void:
    gut.p("\n%s" % title)
    gut.p("| region | tris | in view | mean owner size m | max owner size m | screen px²/tri (in view) | mean key px (we·proj/d) | flagged at floor | flagged above floor | err m p50 / p95 / max | err px p50 / p95 / max |")
    gut.p("|---|---|---|---|---|---|---|---|---|---|---|")
    var ks := t.keys()
    ks.sort()
    for k in ks:
        var g: Agg = t[k]
        gut.p("| %s | %d | %.0f%% | %.2f | %.2f | %.1f | %.3f | %.1f%% | %.1f%% | %.3f / %.3f / %.3f | %.2f / %.2f / %.2f |" % [
                k, g.n, 100.0 * g.in_view / g.n, g.size_sum / g.n, g.size_max,
                g.px_area / maxi(g.px_n, 1), g.key_sum / g.n,
                100.0 * g.flag_floor / g.n, 100.0 * g.flag_cand / g.n,
                g.pctl(g.err_m, 0.5), g.pctl(g.err_m, 0.95), g.pctl(g.err_m, 1.0),
                g.pctl(g.err_px, 0.5), g.pctl(g.err_px, 0.95), g.pctl(g.err_px, 1.0)])


# Flagged-triangle census over owners only (cheap enough for every bloom job): within the drawn
# window, split by region (RIDGE / EDIT / other) and by owner at-floor vs above-floor (a candidate).
func _flag_census(m: DCOctreeMesher, eps: float) -> String:
    var owners := m.get_last_triangle_owners()
    var sizes := m.get_last_triangle_owner_sizes()
    var errs := m.get_last_triangle_owner_errors()
    var win := _window(WIN_R)
    var c := {}
    for t in owners.size():
        var ctr := (owners[t] + Vector3.ONE * (sizes[t] * 0.5)) * bc
        if not _in_box(ctr, win):
            continue
        var d := maxf((ctr - eye).length(), 1e-3)
        var region := "EDIT" if _owner_is_edit(owners[t] * bc, sizes[t] * bc) else ("RIDGE" if d >= 60.0 and _near_crest(ctr) else "other")
        var at := "cand" if sizes[t] * bc > _floor_at(ctr, eps) + 1e-6 else "floor"
        var k := "%s tris" % region
        c[k] = c.get(k, 0) + 1
        if errs[t] * bc * proj / d > eps * 2.0:
            k = "%s flagged %s" % [region, at]
            c[k] = c.get(k, 0) + 1
    var s := ""
    for region in ["RIDGE", "EDIT", "other"]:
        s += "  %s %d tris, flagged floor %d / cand %d;" % [region, c.get("%s tris" % region, 0),
                c.get("%s flagged floor" % region, 0), c.get("%s flagged cand" % region, 0)]
    return s


# --- intent error: the analytic box faces -> the emitted mesh ------------------------------------

class TriHash:
    var h := 0.5
    var cells := {}
    var tris := PackedVector3Array()

    func key(p: Vector3) -> Vector3i:
        return Vector3i((p / h).floor())

    func add(a: Vector3, b: Vector3, c: Vector3) -> void:
        var i := tris.size() / 3
        tris.append_array([a, b, c])
        var lo := key(a.min(b).min(c))
        var hi := key(a.max(b).max(c))
        for x in range(lo.x, hi.x + 1):
            for y in range(lo.y, hi.y + 1):
                for z in range(lo.z, hi.z + 1):
                    var k := Vector3i(x, y, z)
                    if not cells.has(k):
                        cells[k] = PackedInt32Array()
                    cells[k].append(i)

    func near(p: Vector3, r: int) -> Dictionary:
        var out := {}
        var c := key(p)
        for x in range(c.x - r, c.x + r + 1):
            for y in range(c.y - r, c.y + r + 1):
                for z in range(c.z - r, c.z + r + 1):
                    for i in cells.get(Vector3i(x, y, z), PackedInt32Array()):
                        out[i] = true
        return out

    func along(p: Vector3, n: Vector3, reach: float) -> Dictionary:
        var out := {}
        var t := -reach
        while t <= reach + h:
            for i in cells.get(key(p + n * minf(t, reach)), PackedInt32Array()):
                out[i] = true
            t += h * 0.5
        return out


# The triangles near the stonehenge (region + 4 m), hashed.
func _region_hash(arrays: Array) -> TriHash:
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
    var ro := Vector3(root_o)
    var region := _stones_region().grow(4.0)
    var th := TriHash.new()
    th.h = HASH_H
    for t in idx.size() / 3:
        var ia := idx[t * 3]
        var ib := idx[t * 3 + 1]
        var ic := idx[t * 3 + 2]
        if ia == ib or ib == ic or ia == ic:
            continue
        var pa := (verts[ia] + ro) * bc
        var pb := (verts[ib] + ro) * bc
        var pc := (verts[ic] + ro) * bc
        if AABB(pa, Vector3.ZERO).expand(pb).expand(pc).grow(0.01).intersects(region):
            th.add(pa, pb, pc)
    return th


# Closest point on triangle abc to p (Ericson, Real-Time Collision Detection 5.1.5).
func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
    var ab := b - a
    var ac := c - a
    var ap := p - a
    var d1 := ab.dot(ap)
    var d2 := ac.dot(ap)
    if d1 <= 0.0 and d2 <= 0.0:
        return a
    var bp := p - b
    var d3 := ab.dot(bp)
    var d4 := ac.dot(bp)
    if d3 >= 0.0 and d4 <= d3:
        return b
    var vc := d1 * d4 - d3 * d2
    if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
        return a + ab * (d1 / (d1 - d3))
    var cp := p - c
    var d5 := ab.dot(cp)
    var d6 := ac.dot(cp)
    if d6 >= 0.0 and d5 <= d6:
        return c
    var vb := d5 * d2 - d1 * d6
    if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
        return a + ac * (d2 / (d2 - d6))
    var va := d3 * d6 - d5 * d4
    if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
        return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
    var denom := 1.0 / (va + vb + vc)
    return a + ab * (vb * denom) + ac * (vc * denom)


# Nearest mesh distance from p, exact up to NEAR_CAP (returns NEAR_CAP beyond it).
func _nearest_dist(p: Vector3, th: TriHash) -> float:
    var best := NEAR_CAP
    for i in th.near(p, ceili(NEAR_CAP / th.h)):
        var q := _closest_on_tri(p, th.tris[i * 3], th.tris[i * 3 + 1], th.tris[i * 3 + 2])
        best = minf(best, (q - p).length())
    return best


# Nearest mesh hit on the segment p +- RAY_REACH along the face normal n; -1 for none.
func _ray_dist(p: Vector3, n: Vector3, th: TriHash) -> float:
    var a := p - n * RAY_REACH
    var b := p + n * RAY_REACH
    var best := -1.0
    for i in th.along(p, n, RAY_REACH):
        var hit = Geometry3D.segment_intersects_triangle(a, b, th.tris[i * 3], th.tris[i * 3 + 1], th.tris[i * 3 + 2])
        if hit != null:
            var d: float = (hit - p).length()
            best = d if best < 0.0 else minf(best, d)
    return best


func _face_samples(b: AABB) -> Array:
    var out := []
    for axis in 3:
        for side in [0.0, 1.0]:
            var n := Vector3.ZERO
            n[axis] = 1.0 if side > 0.0 else -1.0
            var u := (axis + 1) % 3
            var v := (axis + 2) % 3
            var su := 0.125
            while su < b.size[u]:
                var sv := 0.125
                while sv < b.size[v]:
                    var p := b.position
                    p[axis] += b.size[axis] * side
                    p[u] += su
                    p[v] += sv
                    out.append([p, n])
                    sv += 0.25
                su += 0.25
    return out


class Intent:
    var near := PackedFloat32Array()   # nearest mesh distance, capped at NEAR_CAP
    var hit := PackedFloat32Array()    # along-normal hit distance, hits only
    var miss := 0                      # no mesh on the face normal within +-RAY_REACH
    var n := 0


# Every exposed face sample of every block (exposed: its outward point is air in the intent field,
# so faces buried in ground or against another stone are skipped), measured against the mesh.
# Grouped as uprights / lintels / fallen by block shape.
func _block_intent(arrays: Array) -> Dictionary:
    var th := _region_hash(arrays)
    var out := {}
    for b in blocks:
        var kind := "upright" if b.size.y >= 4.0 else ("lintel" if b.size.x + b.size.z > 5.0 else "fallen")
        var g: Intent = out.get_or_add(kind, Intent.new())
        var all: Intent = out.get_or_add("all", Intent.new())
        for s in _face_samples(b):
            var p: Vector3 = s[0]
            var n: Vector3 = s[1]
            if _intent_sdist(p + n * 0.3) < 0.0:
                continue
            var nd := _nearest_dist(p, th)
            var rd := _ray_dist(p, n, th)
            for x in [g, all]:
                x.n += 1
                x.near.append(nd)
                if rd < 0.0:
                    x.miss += 1
                else:
                    x.hit.append(rd)
    return out


func _print_intent(title: String, r: Dictionary) -> void:
    var a := Agg.new()
    var line := ""
    for k in ["all", "upright", "lintel", "fallen"]:
        if not r.has(k):
            continue
        var g: Intent = r[k]
        var far := 0
        for x in g.near:
            far += 1 if x > 0.25 else 0
        line += "\n    %-8s samples %4d | nearest mesh p50 %.3f p95 %s m, >0.25 m %.1f%% | along-normal miss %.1f%%, hit dist p50 %.3f p95 %.3f m" % [
                k, g.n, a.pctl(g.near, 0.5),
                (">=%.1f" % NEAR_CAP) if a.pctl(g.near, 0.95) >= NEAR_CAP else "%.3f" % a.pctl(g.near, 0.95),
                100.0 * far / maxi(g.n, 1), 100.0 * g.miss / maxi(g.n, 1), a.pctl(g.hit, 0.5), a.pctl(g.hit, 0.95)]
    gut.p("%s%s" % [title, line])


# Edge use counts among the region's triangles near the blocks (a watertight 2-manifold uses each
# edge exactly twice).
func _hole_audit(arrays: Array) -> void:
    var th := _region_hash(arrays)
    var uses := {}
    for i in range(0, th.tris.size(), 3):
        var t := th.tris
        for e in [[t[i], t[i + 1]], [t[i + 1], t[i + 2]], [t[i + 2], t[i]]]:
            if not (_near_block(e[0], 1.5) and _near_block(e[1], 1.5)):
                continue
            var ka := Vector3i((e[0] * 1024.0).round())
            var kb := Vector3i((e[1] * 1024.0).round())
            var k := [ka, kb] if ka < kb else [kb, ka]
            uses[k] = uses.get(k, 0) + 1
    var open := 0
    var over := 0
    for k in uses:
        open += 1 if uses[k] == 1 else 0
        over += 1 if uses[k] > 2 else 0
    gut.p("    edge audit near blocks: edges %d  open (used once) %d  non-manifold (>2) %d" % [uses.size(), open, over])


func _near_block(q: Vector3, r: float) -> bool:
    for b in blocks:
        if b.grow(r).has_point(q):
            return true
    return false


# --- Hermite normals and the exact-Hermite oracle --------------------------------------------------

func _grad_raw(s: EditStore, p: Vector3, h: float) -> Vector3:
    return Vector3(s.sample(p + Vector3(h, 0, 0)) - s.sample(p - Vector3(h, 0, 0)),
            s.sample(p + Vector3(0, h, 0)) - s.sample(p - Vector3(0, h, 0)),
            s.sample(p + Vector3(0, 0, h)) - s.sample(p - Vector3(0, 0, h))) / (2.0 * h)


func _grad(p: Vector3, h: float) -> Vector3:
    var g := _grad_raw(store, p, h)
    return g.normalized() if g.length_squared() > 0.0 else Vector3.UP


# At the lattice-edge zero crossings leaf_qef samples (linear crossing of stored corners), compare
# the mesher's normal (EditStoreSource::gradient, h = 1 lattice unit) with (a) the stored field's own
# fine gradient (h = 0.05 unit: the trilinear interpolant's slope) and (b) the analytic normal of the
# intent surface there (the box face, where a box is the nearer surface; ground elsewhere).
func _gradient_section() -> void:
    var region := _stones_region()
    _gradient_row("stones (crossings within 0.5 m of a block, box is the intent surface)", region.grow(1.0), true)
    _gradient_row("generator ground, 30 m beside", AABB(region.position + Vector3(-30, -6, 0), region.size + Vector3(0, 6, 0)), false)


func _gradient_row(label: String, box: AABB, near_blocks: bool) -> void:
    var vs_fine := PackedFloat32Array()
    var vs_true := PackedFloat32Array()
    var lo := Vector3i((box.position / bc).floor())
    var hi := Vector3i((box.end / bc).ceil())
    for x in range(lo.x, hi.x):
        for y in range(lo.y, hi.y):
            for z in range(lo.z, hi.z):
                var p := Vector3(x, y, z) * bc
                for dir in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
                    var fa := store.sample(p)
                    var fb := store.sample(p + dir * bc)
                    if (fa < 0.0) == (fb < 0.0) or fa == fb:
                        continue
                    var q := p.lerp(p + dir * bc, fa / (fa - fb))
                    if near_blocks != _near_block(q, 0.5):
                        continue
                    var on_box := _box_union(q) < _gen_sdist(q)
                    if near_blocks and not on_box:
                        continue
                    var mesher := _grad(q, bc)
                    var truth := _box_union_grad(q) if on_box else _grad_raw(gen, q, 0.05).normalized()
                    vs_fine.append(rad_to_deg(mesher.angle_to(_grad(q, 0.05 * bc))))
                    vs_true.append(rad_to_deg(mesher.angle_to(truth)))
    var a := Agg.new()
    gut.p("  %s: crossings %d | vs stored-field fine gradient p50 %.1f p90 %.1f max %.1f deg | vs analytic intent normal p50 %.1f p90 %.1f max %.1f deg, >30 deg %.0f%%" % [
            label, vs_fine.size(), a.pctl(vs_fine, 0.5), a.pctl(vs_fine, 0.9), a.pctl(vs_fine, 1.0),
            a.pctl(vs_true, 0.5), a.pctl(vs_true, 0.9), a.pctl(vs_true, 1.0), 100.0 * _count_over(vs_true, 30.0) / maxi(vs_true.size(), 1)])


func _count_over(a: PackedFloat32Array, t: float) -> int:
    var n := 0
    for x in a:
        n += 1 if x > t else 0
    return n


const CUBE_EDGES := [
    [Vector3i(0, 0, 0), Vector3i(1, 0, 0)], [Vector3i(0, 1, 0), Vector3i(1, 1, 0)],
    [Vector3i(0, 0, 1), Vector3i(1, 0, 1)], [Vector3i(0, 1, 1), Vector3i(1, 1, 1)],
    [Vector3i(0, 0, 0), Vector3i(0, 1, 0)], [Vector3i(1, 0, 0), Vector3i(1, 1, 0)],
    [Vector3i(0, 0, 1), Vector3i(0, 1, 1)], [Vector3i(1, 0, 1), Vector3i(1, 1, 1)],
    [Vector3i(0, 0, 0), Vector3i(0, 0, 1)], [Vector3i(1, 0, 0), Vector3i(1, 0, 1)],
    [Vector3i(0, 1, 0), Vector3i(0, 1, 1)], [Vector3i(1, 1, 0), Vector3i(1, 1, 1)]]


# Oracle for "what would exact Hermite data buy at the SAME 1 m lattice": for every leaf cell near the
# stones, solve its QEF two ways, both with the stored corners' signs (so topology is the store's):
#   scalar  -- leaf_qef's recipe: linear crossing of the stored corners + the h = 1 gradient;
#   hermite -- the exact crossing of min(generator, analytic boxes) on that edge + its analytic normal.
# The solve is a GDScript port of Qef::solve (dc_qef.h). Scalar vertices are checked against the
# mesher's own floor-mesh vertices, so the port is validated. Error = |intent signed distance| at the
# vertex, for cells whose exact vertex lies on a stone (box nearer than ground).
func _hermite_oracle(floor_arrays: Array) -> void:
    var mesh_v := {}
    var ro := Vector3(root_o)
    for v in floor_arrays[Mesh.ARRAY_VERTEX]:
        var w: Vector3 = (v + ro) * bc
        mesh_v.get_or_add(Vector3i((w / bc).floor()), []).append(w)
    var region := _stones_region().grow(1.0)
    var lo := Vector3i((region.position / bc).floor())
    var hi := Vector3i((region.end / bc).ceil())
    var err_s := PackedFloat32Array()
    var err_h := PackedFloat32Array()
    var cross_d := PackedFloat32Array()
    var port_d := PackedFloat32Array()
    for x in range(lo.x, hi.x):
        for y in range(lo.y, hi.y):
            for z in range(lo.z, hi.z):
                var o := Vector3i(x, y, z)
                var qs := MiniQef.new()
                var qh := MiniQef.new()
                for e in CUBE_EDGES:
                    var pa := Vector3(o + e[0]) * bc
                    var pb := Vector3(o + e[1]) * bc
                    var fa := store.sample(pa)
                    var fb := store.sample(pb)
                    if (fa < 0.0) == (fb < 0.0) or fa == fb:
                        continue
                    var q_lin := pa.lerp(pb, fa / (fa - fb))
                    qs.add(q_lin, _grad(q_lin, bc))
                    var q_ex := _exact_crossing(pa, pb, fa < 0.0)
                    cross_d.append((q_ex - q_lin).length())
                    var on_box := _box_union(q_ex) < _gen_sdist(q_ex)
                    qh.add(q_ex, _box_union_grad(q_ex) if on_box else _grad_raw(gen, q_ex, 0.05).normalized())
                if qs.count == 0:
                    continue
                var cmin := Vector3(o) * bc
                var cmax := cmin + Vector3.ONE * bc
                var vs := qs.solve(cmin, cmax)
                var vh := qh.solve(cmin, cmax)
                var best := 1e9
                for w in mesh_v.get(o, []):
                    best = minf(best, (w - vs).length())
                port_d.append(best)
                if _box_union(vh) > _gen_sdist(vh):
                    continue
                err_s.append(absf(_intent_sdist(vs)))
                err_h.append(absf(_intent_sdist(vh)))
    var a := Agg.new()
    var matched := 0
    var with_v := 0
    for d in port_d:
        with_v += 1 if d < 1e8 else 0
        matched += 1 if d < 1e-3 else 0
    gut.p("  HERMITE ORACLE (1 m leaves near the stones). Port check: of %d cells with crossings, %d hold a mesher vertex, and %d of those match the ported scalar solve within 1 mm" % [
            port_d.size(), with_v, matched])
    gut.p("    crossing shift, linear vs exact: p50 %.3f p95 %.3f max %.3f m (%d edges)" % [
            a.pctl(cross_d, 0.5), a.pctl(cross_d, 0.95), a.pctl(cross_d, 1.0), cross_d.size()])
    gut.p("    stone-cell vertex error to intent: scalar p50 %.3f p95 %.3f max %.3f m | exact Hermite p50 %.3f p95 %.3f max %.3f m (%d cells)" % [
            a.pctl(err_s, 0.5), a.pctl(err_s, 0.95), a.pctl(err_s, 1.0),
            a.pctl(err_h, 0.5), a.pctl(err_h, 0.95), a.pctl(err_h, 1.0), err_s.size()])


# Bisect the intent field on the edge pa -> pb; `a_inside` is the stored sign at pa.
func _exact_crossing(pa: Vector3, pb: Vector3, a_inside: bool) -> Vector3:
    var lo := 0.0
    var hi := 1.0
    for _i in 30:
        var mid := (lo + hi) * 0.5
        if (_intent_sdist(pa.lerp(pb, mid)) < 0.0) == a_inside:
            lo = mid
        else:
            hi = mid
    return pa.lerp(pb, (lo + hi) * 0.5)


class MiniQef:
    var a := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
    var atb := Vector3.ZERO
    var mass := Vector3.ZERO
    var count := 0

    func add(p: Vector3, n_in: Vector3) -> void:
        var n := n_in.normalized()
        for i in 3:
            for j in 3:
                a[i][j] += n[i] * n[j]
        atb += n * n.dot(p)
        mass += p
        count += 1

    func mul(v: Vector3) -> Vector3:
        return Vector3(a[0][0] * v.x + a[0][1] * v.y + a[0][2] * v.z,
                a[1][0] * v.x + a[1][1] * v.y + a[1][2] * v.z,
                a[2][0] * v.x + a[2][1] * v.y + a[2][2] * v.z)

    # Qef::eigen + Qef::solve, line for line.
    func solve(cmin: Vector3, cmax: Vector3) -> Vector3:
        var c := mass / float(count)
        var rhs := atb - mul(c)
        var m := [a[0].duplicate(), a[1].duplicate(), a[2].duplicate()]
        var v := [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
        for _sweep in 12:
            var p := 0
            var q := 1
            var best := absf(m[0][1])
            if absf(m[0][2]) > best:
                best = absf(m[0][2])
                p = 0
                q = 2
            if absf(m[1][2]) > best:
                best = absf(m[1][2])
                p = 1
                q = 2
            if best < 1e-14:
                break
            var app: float = m[p][p]
            var aqq: float = m[q][q]
            var apq: float = m[p][q]
            var phi := 0.5 * atan2(2.0 * apq, app - aqq)
            var co := cos(phi)
            var si := sin(phi)
            var r := 3 - p - q
            m[p][p] = co * co * app + 2.0 * si * co * apq + si * si * aqq
            m[q][q] = si * si * app - 2.0 * si * co * apq + co * co * aqq
            m[p][q] = 0.0
            m[q][p] = 0.0
            var arp: float = m[r][p]
            var arq: float = m[r][q]
            m[p][r] = co * arp + si * arq
            m[r][p] = m[p][r]
            m[q][r] = -si * arp + co * arq
            m[r][q] = m[q][r]
            for row in 3:
                var vp: float = v[row][p]
                var vq: float = v[row][q]
                v[row][p] = co * vp + si * vq
                v[row][q] = -si * vp + co * vq
        var vals := Vector3(m[0][0], m[1][1], m[2][2])
        var vmax := maxf(absf(vals.x), maxf(absf(vals.y), absf(vals.z)))
        var off := Vector3.ZERO
        if vmax > 0.0:
            for i in 3:
                if absf(vals[i]) <= vmax * 1e-3:
                    continue
                var vec := Vector3(v[0][i], v[1][i], v[2][i])
                off += vec * (vec.dot(rhs) / vals[i])
        var x := c + off
        if x.x < cmin.x or x.y < cmin.y or x.z < cmin.z or x.x > cmax.x or x.y > cmax.y or x.z > cmax.z:
            return c.clamp(cmin, cmax)
        return x


# --- section 1: steady state (a fully refined tree, collapse decides) --------------------------------

func _steady_state_section() -> void:
    gut.p("\n===== STEADY STATE (phase %.2f): mesh_world to the floor (as after an edit's full rebuild), then remesh at other eps =====" % phase)
    var ref := _new_mesher()
    var t0 := Time.get_ticks_msec()
    var ref_arrays := _build(ref, EPS_MIN, false)
    gut.p("floor reference (error_driven=false, eps %.1f): cells %d  %d ms" % [EPS_MIN, ref.get_octree_cell_count(), Time.get_ticks_msec() - t0])
    _print_tri_table("FLOOR REFERENCE (no collapse; the best this 1 m data can give)", _tri_table(ref_arrays, ref, EPS_MIN))
    _print_intent("INTENT floor-ref", _block_intent(ref_arrays))
    var m := _new_mesher()
    var arrays := _build(m, EPS_MIN, true)
    for eps in [EPS_MIN, 2.0, 8.0, EPS_START]:
        if eps != EPS_MIN:
            arrays = m.remesh(cam_l, proj, eps)
        _print_tri_table("LIVE COLLAPSE eps %.1f px" % eps, _tri_table(arrays, m, eps))
        _print_intent("INTENT collapse eps %.1f" % eps, _block_intent(arrays))


# --- section 2: the bloom (count-budgeted refine, frontier) ----------------------------------------

# Replays DcWorldPreview from arrival: a full build at EPS_START, then per job eps x0.9 until EPS_MIN
# with POPS_PER_JOB refines (the first grow of a job rebuilds the frontier for the new eps, as the
# live job does), then drains of POPS_PER_JOB pops each. collapse=false gives an exact frontier view
# (every emitting owner is a structural leaf; one above its floor IS an unrefined candidate);
# collapse=true is what's drawn. Every job prints the flagged-triangle census.
func _bloom_section(collapse: bool, marks: Array) -> void:
    gut.p("\n===== BLOOM (%s), %d pops per job =====" % ["live collapse" if collapse else "no collapse -> exact frontier", POPS_PER_JOB])
    var m := _new_mesher()
    m.set_emit_diff(true)
    var eps := EPS_START
    var emit_r := WIN_R if collapse else RETAIN_R
    var arrays := _build(m, eps, collapse)
    gut.p("job 1  eps %.2f  cells %d |%s" % [eps, m.get_octree_cell_count(), _flag_census(m, eps)])
    var jobs := 1
    var marked_mid := false
    while eps > EPS_MIN:
        eps = maxf(eps * 0.9, EPS_MIN)
        arrays = _grow_pops(m, eps, POPS_PER_JOB, true, emit_r)
        jobs += 1
        gut.p("job %d  eps %.2f  cells %d  queue %d |%s" % [jobs, eps, m.get_octree_cell_count(), m.get_last_refine_queue_size(), _flag_census(m, eps)])
        if not marked_mid and eps <= MID_EPS:
            marked_mid = true
            _bloom_mark(m, arrays, eps, collapse, "descent, job %d" % jobs)
    var drains := 0
    for mark in marks:
        while drains < mark and m.get_refine_pending():
            arrays = _grow_pops(m, eps, POPS_PER_JOB, false, emit_r)
            drains += 1
        _bloom_mark(m, arrays, eps, collapse, "eps floor + %d drains (job %d)" % [drains, jobs + drains])
        if not collapse and mark == 0:
            _pop_trace(m, eps, emit_r)
            m.set_emit_diff(true)


func _bloom_mark(m: DCOctreeMesher, arrays: Array, eps: float, collapse: bool, label: String) -> void:
    gut.p("\n--- %s  eps %.2f  cells %d  queue %d  pending %s  drawn tris %d ---" % [
            label, eps, m.get_octree_cell_count(), m.get_last_refine_queue_size(), m.get_refine_pending(),
            m.get_last_triangle_owners().size()])
    if collapse:
        _print_tri_table("MESH (%s)" % label, _tri_table(arrays, m, eps))
        _print_intent("INTENT (%s)" % label, _block_intent(arrays))
    else:
        _frontier_table(arrays, m, eps)


# Every emitting owner above its graded floor is a deferred frontier candidate (no collapse here,
# so no internal node emits). Its owner error IS its heap key `we` (verr_cache = the same residual).
# Candidates that emit nothing are invisible here: queue - seen.
func _frontier_table(arrays: Array, m: DCOctreeMesher, eps: float) -> void:
    var cands := _collect_candidates(arrays, m, eps)
    var under := 0
    for c in cands:
        under += 1 if c.we * proj / c.d <= eps else 0
    gut.p("frontier: queue %d, visible candidates %d (the rest emit no triangle); visible candidates whose screen key we·proj/d <= eps already: %d (%.1f%%)" % [
            m.get_last_refine_queue_size(), cands.size(), under, 100.0 * under / maxi(cands.size(), 1)])
    var by_we := cands.duplicate()
    by_we.sort_custom(func(x, y): return x.we > y.we)
    var by_screen := cands.duplicate()
    by_screen.sort_custom(func(x, y): return x.we * proj / x.d > y.we * proj / y.d)
    gut.p("| region | candidates | in view | mean dist m | mean size | we p50 / max (lattice) | screen key p50 / max px | nspread p50 deg | best rank by we | best rank by screen key |")
    gut.p("|---|---|---|---|---|---|---|---|---|---|")
    var groups := {}
    for c in cands:
        groups.get_or_add(c.region, []).append(c)
    var ks := groups.keys()
    ks.sort()
    for k in ks:
        _frontier_row(k, groups[k], by_we, by_screen)
    _top_composition("top 200 by we (the live heap order)", by_we)
    _top_composition("top 200 by we*proj/d (screen key, doc 20 P)", by_screen)


func _collect_candidates(arrays: Array, m: DCOctreeMesher, eps: float) -> Array:
    var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
    var owners := m.get_last_triangle_owners()
    var sizes := m.get_last_triangle_owner_sizes()
    var errs := m.get_last_triangle_owner_errors()
    var seen := {}
    for t in owners.size():
        var ia := idx[t * 3]
        var ib := idx[t * 3 + 1]
        var ic := idx[t * 3 + 2]
        if ia == ib or ib == ic or ia == ic:
            continue
        var ctr := (owners[t] + Vector3.ONE * (sizes[t] * 0.5)) * bc
        if sizes[t] * bc <= _floor_at(ctr, eps):
            continue
        var key := Vector4(owners[t].x, owners[t].y, owners[t].z, sizes[t])
        var spread := _normal_spread_deg(norms, ia, ib, ic)
        if seen.has(key):
            seen[key].spread = maxf(seen[key].spread, spread)
            continue
        var c := Cand.new()
        c.d = maxf((ctr - eye).length(), 1e-3)
        c.we = errs[t]
        c.size = sizes[t] * bc
        c.spread = spread
        c.view = _in_frustum(ctr)
        c.drawn = _in_box(ctr, _window(WIN_R))
        c.edit = _owner_is_edit(owners[t] * bc, sizes[t] * bc)
        c.ridge = not c.edit and c.d >= 60.0 and _near_crest(ctr)
        seen[key] = c
    for c in seen.values():
        c.region = _cand_region(c)
    return seen.values()


class Cand:
    var d := 0.0
    var we := 0.0
    var size := 0.0
    var spread := 0.0
    var view := false
    var drawn := false
    var edit := false
    var ridge := false
    var region := ""


func _frontier_row(k: String, g: Array, by_we: Array, by_screen: Array) -> void:
    var wes := PackedFloat32Array()
    var keys := PackedFloat32Array()
    var spreads := PackedFloat32Array()
    var dsum := 0.0
    var ssum := 0.0
    var view := 0
    for c in g:
        wes.append(c.we)
        keys.append(c.we * proj / c.d)
        spreads.append(c.spread)
        dsum += c.d
        ssum += c.size
        view += 1 if c.view else 0
    var a := Agg.new()
    gut.p("| %s | %d | %.0f%% | %.0f | %.1f | %.3f / %.3f | %.2f / %.2f | %.0f | %d | %d |" % [
            k, g.size(), 100.0 * view / g.size(), dsum / g.size(), ssum / g.size(),
            a.pctl(wes, 0.5), a.pctl(wes, 1.0), a.pctl(keys, 0.5), a.pctl(keys, 1.0), a.pctl(spreads, 0.5),
            _best_rank(by_we, k), _best_rank(by_screen, k)])


func _best_rank(sorted: Array, region: String) -> int:
    for i in sorted.size():
        if sorted[i].region == region:
            return i
    return -1


func _top_composition(title: String, sorted: Array) -> void:
    var counts := {}
    var view := 0
    var n := mini(200, sorted.size())
    for i in n:
        counts[sorted[i].region] = counts.get(sorted[i].region, 0) + 1
        view += 1 if sorted[i].view else 0
    gut.p("%s: %s  (in view %d/%d)" % [title, counts, view, n])


# Exact pop order: budget 0 refines exactly one candidate per grow. With emit_diff off, a drain's
# incremental emit appends the new leaves' triangles at the end of the persistent arrays, so
# owners[prev_n:] not seen before are the popped cell's children.
func _pop_trace(m: DCOctreeMesher, eps: float, emit_r: int) -> void:
    m.set_emit_diff(false)
    _grow(m, eps, 0, true, emit_r)
    var known := {}
    var owners := m.get_last_triangle_owners()
    var sizes := m.get_last_triangle_owner_sizes()
    for t in owners.size():
        known[Vector4(owners[t].x, owners[t].y, owners[t].z, sizes[t])] = true
    var prev_n := owners.size()
    var tally := {}
    var dists := PackedFloat32Array()
    var unseen := 0
    var grew := 0
    for _p in POP_TRACE:
        if not m.get_refine_pending():
            break
        var cells0 := m.get_octree_cell_count()
        _grow(m, eps, 0, true, emit_r)
        grew += 1 if m.get_octree_cell_count() > cells0 else 0
        owners = m.get_last_triangle_owners()
        sizes = m.get_last_triangle_owner_sizes()
        var box := AABB()
        var found := false
        var from := prev_n if owners.size() >= prev_n else 0
        for t in range(from, owners.size()):
            var k := Vector4(owners[t].x, owners[t].y, owners[t].z, sizes[t])
            if known.has(k):
                continue
            known[k] = true
            var cell := AABB(owners[t] * bc, Vector3.ONE * (sizes[t] * bc))
            box = cell if not found else box.merge(cell)
            found = true
        prev_n = owners.size()
        if not found:
            unseen += 1
            continue
        var ctr := box.get_center()
        var d := (ctr - eye).length()
        var edit := _owner_is_edit(box.position, box.size.x)
        var r := "EDIT" if edit else ("RIDGE" if d >= 60.0 and _near_crest(ctr) else "gen %s" % _band(d))
        r += "" if _in_box(ctr, _window(WIN_R)) else " (undrawn ring)"
        tally[r] = tally.get(r, 0) + 1
        dists.append(d)
    var a := Agg.new()
    gut.p("\nPOP TRACE (first %d single pops at eps %.2f; %d grew the tree): %s  no-new-triangle pops %d  dist p10/p50/p90 %.0f/%.0f/%.0f m" % [
            POP_TRACE, eps, grew, tally, unseen, a.pctl(dists, 0.1), a.pctl(dists, 0.5), a.pctl(dists, 0.9)])


# --- section 3: stone quality across placement phase, 1 m and 0.25 m -------------------------------

# Construction placement is free (build_placement_pos = hit + offset), so a part's faces land at any
# phase against the lattice. Re-imprint the stones at each phase and measure the stone region at the
# live 1 m lattice and at 0.25 m (RENDER_SUBDIV_LOG2 = 2: imprint and mesh together).
func _phase_sweep_section() -> void:
    for p in PHASES:
        _subdiv_section(1.0, 1.0, p)
        _subdiv_section(SUB_CELL, SUB_CELL, p)


# Fresh store, stones imprinted at min_leaf `leaf`, meshed at base cell `cell` over +-SUB_WIN_R.
func _subdiv_section(cell: float, leaf: float, p_phase: float) -> void:
    _restage(cell, leaf, p_phase)
    gut.p("\n===== STONES: phase %.2f, mesh base cell %.2f m, imprint cell %.2f m, window +-%d m =====" % [phase, bc, stamp_leaf, SUB_WIN_R])
    _gradient_section()
    var ref := _new_mesher()
    var t0 := Time.get_ticks_msec()
    var ref_arrays := _build(ref, EPS_MIN, false, SUB_WIN_R)
    gut.p("floor reference: cells %d  %d ms" % [ref.get_octree_cell_count(), Time.get_ticks_msec() - t0])
    if bc == 1.0 and stamp_leaf == 1.0:
        _hermite_oracle(ref_arrays)
    _print_tri_table("FLOOR REFERENCE (no collapse)", _edit_only(_tri_table(ref_arrays, ref, EPS_MIN)))
    _print_intent("INTENT floor-ref", _block_intent(ref_arrays))
    _hole_audit(ref_arrays)
    var m := _new_mesher()
    var arrays := _build(m, EPS_MIN, true, SUB_WIN_R)
    _print_tri_table("LIVE COLLAPSE eps %.1f px" % EPS_MIN, _edit_only(_tri_table(arrays, m, EPS_MIN)))
    _print_intent("INTENT collapse eps %.1f" % EPS_MIN, _block_intent(arrays))


func _edit_only(t: Dictionary) -> Dictionary:
    var out := {}
    for k in t:
        if k.begins_with("EDIT"):
            out[k] = t[k]
    return out
