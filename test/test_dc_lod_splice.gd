extends GutTest

# Gate test for B1 — Multi-LOD splice. Validates that the PRODUCTION sub-octree splice path
# reproduces the full build across a LOD transition: a SMALL octree at sub_origin (sub_depth, not
# the full DEPTH) with level-origins / center / camera shifted into its local frame, incremental on
# the shared collapse set, output restricted to the edit core box. If any of that math — or the
# sub-box ALIGNMENT — is wrong, the patch will not reproduce the full build's triangles in the box
# and the seam cracks. The full build is the oracle (the cache the live splice patches against).
#
# Field: an analytic 2-level sphere clipmap. Analytic is correct HERE because the oracle is the full
# build on the SAME field — this test isolates the coordinate transform + boundary stitching, not
# the field's fidelity (the real-terrain watertight guards live in test_dc_real_terrain.gd /
# test_dc_incremental_splice.gd). A finite HALF0 forces the sphere surface through the level-0/1
# boundary so coarse (collapsed) cells appear outside the fine core — the cells B1 must patch.

const SIZE   := 64
const DIM    := SIZE + 1                 # 65 samples per level per axis
const DEPTH  := 6                        # octree root [0,64]^3
const HALF0  := 12.0                     # level-0 half-extent; level-1 used at Chebyshev > 12
const CENTER := Vector3(32, 32, 32)
const RADIUS := 24.0                     # sphere surface crosses the LOD band
const PROJ   := 500.0
const EPS_PX := 2.0                      # error-driven collapse → coarse cells far from camera
const CAMERA := Vector3(32, 300, 32)     # high above; the far side of the sphere collapses


# Sphere SDF over a DIM^3 grid sampled at world p = origin + (x,y,z)*cell (so level k uses cell 2^k).
func _grid(origin: Vector3i, cell: float) -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(DIM * DIM * DIM)
    var i := 0
    for z in DIM:
        for y in DIM:
            for x in DIM:
                var p := Vector3(origin) + Vector3(x, y, z) * cell
                data[i] = p.distance_to(CENTER) - RADIUS
                i += 1
    return data


# Two-level clipmap covering the root: level 0 (cell 1) over [0,64], level 1 (cell 2) over [0,128].
# Both origins ZERO (data[idx] = field at world idx*cell), as the analytic field is position-pure.
func _clip() -> Dictionary:
    return {
        "data":    [_grid(Vector3i.ZERO, 1.0), _grid(Vector3i.ZERO, 2.0)],
        "origins": PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
        "cells":   PackedFloat32Array([1.0, 2.0]),
    }


static func _snap_dn(v: int, c: int) -> int:
    @warning_ignore("integer_division")
    return (v / c) * c if v >= 0 else ((v - c + 1) / c) * c

static func _snap_up(v: int, c: int) -> int:
    @warning_ignore("integer_division")
    return ((v + c - 1) / c) * c if v >= 0 else (v / c) * c


func _edge_audit_welded(verts: PackedVector3Array, idx: PackedInt32Array) -> Dictionary:
    var key_fn := func(v: Vector3) -> Vector3i:
        return Vector3i(roundi(v.x * 16.0), roundi(v.y * 16.0), roundi(v.z * 16.0))
    var vert_ids := {}
    for i in verts.size():
        var k: Vector3i = key_fn.call(verts[i])
        if not vert_ids.has(k):
            vert_ids[k] = vert_ids.size()
    var counts := {}
    for i in range(0, idx.size(), 3):
        var vi: Array = [vert_ids[key_fn.call(verts[idx[i]])],
                         vert_ids[key_fn.call(verts[idx[i+1]])],
                         vert_ids[key_fn.call(verts[idx[i+2]])]]
        for e in [[vi[0], vi[1]], [vi[1], vi[2]], [vi[2], vi[0]]]:
            var ek := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
            counts[ek] = counts.get(ek, 0) + 1
    var boundary := 0
    var nonmanifold := 0
    for k in counts:
        if counts[k] == 1:   boundary    += 1
        elif counts[k] > 2:  nonmanifold += 1
    return {"boundary": boundary, "nonmanifold": nonmanifold}


func _tris_in_box(arrays: Array, owners: PackedVector3Array, mn: Vector3i, mx: Vector3i) -> Array:
    var tris: Array = []
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx:   PackedInt32Array   = arrays[Mesh.ARRAY_INDEX]
    for t in owners.size():
        var o: Vector3 = owners[t]
        if o.x >= mn.x and o.x < mx.x and o.y >= mn.y and o.y < mx.y and o.z >= mn.z and o.z < mx.z:
            tris.append([verts[idx[t*3]], verts[idx[t*3+1]], verts[idx[t*3+2]]])
    return tris


# Owner sizes round-trip: one positive power-of-two float per triangle.
func test_owner_sizes_parallel_to_owners() -> void:
    var clip := _clip()
    var mesher := DCOctreeMesher.new()
    var arrays := mesher.mesh_clipmap(clip.data, DIM, clip.origins, clip.cells,
        CENTER, HALF0, DEPTH, CAMERA, PROJ, EPS_PX, true, Vector3i.ZERO)
    assert_false(arrays.is_empty(), "produced a surface")
    var owners := mesher.get_last_triangle_owners()
    var sizes  := mesher.get_last_triangle_owner_sizes()
    assert_eq(sizes.size(), owners.size(), "one size per triangle")
    for i in sizes.size():
        var s := int(sizes[i])
        assert_true(s > 0 and (s & (s - 1)) == 0, "size is power-of-two (tri %d = %d)" % [i, s])


# THE GATE TEST: the production sub-octree splice reproduces the full build across a LOD transition.
func test_suboctree_splice_reproduces_full_build_across_lod() -> void:
    var clip := _clip()
    var cache_origin := Vector3i.ZERO

    # A. Full build (the oracle); also populates the collapse hysteresis on this mesher.
    var mesher := DCOctreeMesher.new()
    var full := mesher.mesh_clipmap(clip.data, DIM, clip.origins, clip.cells,
        CENTER, HALF0, DEPTH, CAMERA, PROJ, EPS_PX, true, cache_origin)
    assert_false(full.is_empty(), "full build produced a surface")
    var full_owners := mesher.get_last_triangle_owners()
    var full_sizes  := mesher.get_last_triangle_owner_sizes()

    # B+C. Pick a coarse cell (size>1, Chebyshev > HALF0) whose iteratively-aligned splice sub-box
    # stays inside the root [0,SIZE] (the synthetic field is finite; a real clipmap extends past any
    # edit). Geometry mirrors _dispatch_splice EXACTLY, including the iterative alignment trap.
    var align_cell := 0
    var core_min:   Vector3i
    var core_max:   Vector3i
    var sub_origin: Vector3i
    var sub_size  := 0
    var sub_depth := 0
    for t0 in full_owners.size():
        if int(full_sizes[t0]) <= 1:
            continue
        var ci := Vector3i(full_owners[t0])
        var cheb := maxi(absi(ci.x - int(CENTER.x)), maxi(absi(ci.y - int(CENTER.y)), absi(ci.z - int(CENTER.z))))
        if cheb <= int(HALF0):
            continue
        var mn := ci
        var mx := ci + Vector3i.ONE * int(full_sizes[t0])
        var al := 1
        var cmin: Vector3i
        var cmax: Vector3i
        var so:   Vector3i
        var shi:  Vector3i
        for _it in 8:
            cmin = Vector3i(_snap_dn(mn.x, al), _snap_dn(mn.y, al), _snap_dn(mn.z, al)) - Vector3i.ONE * al
            cmax = Vector3i(_snap_up(mx.x, al), _snap_up(mx.y, al), _snap_up(mx.z, al)) + Vector3i.ONE * al
            var ap := 2 * maxi(4, al)   # 2 align-cells of ring context (mirrors _dispatch_splice)
            so  = cmin - Vector3i.ONE * ap
            shi = cmax + Vector3i.ONE * ap
            var grown := 1
            for t in full_owners.size():
                var o: Vector3 = full_owners[t]
                var sz := int(full_sizes[t])
                if o.x + sz > so.x and o.x < shi.x and o.y + sz > so.y and o.y < shi.y and o.z + sz > so.z and o.z < shi.z:
                    grown = maxi(grown, sz)
            if grown <= al:
                break
            al = grown
        var span := maxi(shi.x - so.x, maxi(shi.y - so.y, shi.z - so.z))
        var ss := 1
        while ss < span:
            ss <<= 1
        if so.x < 0 or so.y < 0 or so.z < 0:
            continue
        if so.x + ss > SIZE or so.y + ss > SIZE or so.z + ss > SIZE:
            continue
        align_cell = al; core_min = cmin; core_max = cmax; sub_origin = so; sub_size = ss
        var tmp := ss
        while tmp > 1:
            tmp >>= 1
            sub_depth += 1
        break
    assert_gt(align_cell, 0, "found an interior LOD-transition cell whose aligned sub-box fits the root")

    # The coordinate transform under test (mirrors _splice_job): shift into the sub-octree frame.
    var root_offset := sub_origin - cache_origin
    var sub_level_origins := PackedVector3Array()
    for k in clip.origins.size():
        sub_level_origins.append(clip.origins[k] - Vector3(root_offset))
    var sub_center := (Vector3(cache_origin) + CENTER) - Vector3(sub_origin)
    var sub_camera := (Vector3(cache_origin) + CAMERA) - Vector3(sub_origin)
    gut.p("align=%d core %s..%s sub_origin=%s sub_size=%d sub_depth=%d" % [
        align_cell, core_min, core_max, sub_origin, sub_size, sub_depth])

    # D. The splice: small octree (sub_depth) at sub_origin, incremental (inherits the full build's
    # hysteresis), output restricted to the core box. Reuses the full grids (the sub-box is interior).
    var patch := mesher.mesh_clipmap(clip.data, DIM, sub_level_origins, clip.cells,
        sub_center, HALF0, sub_depth, sub_camera, PROJ, EPS_PX, true, sub_origin,
        [], PackedColorArray(), false, 0.0, core_min, core_max, true, align_cell)
    var patch_owners := mesher.get_last_triangle_owners()

    # E. Patch verts are in the sub-octree's local frame; shift by sub_origin to compare in world.
    var shift := Vector3(sub_origin)
    var full_core  := _tris_in_box(full,  full_owners,  core_min, core_max)
    var patch_core := _tris_in_box(patch, patch_owners, core_min, core_max)
    gut.p("full_core=%d patch_core=%d" % [full_core.size(), patch_core.size()])
    assert_gt(full_core.size(), 0, "full build has triangles in the core box")
    assert_eq(patch_core.size(), full_core.size(),
        "sub-octree patch reproduces the full build's triangle COUNT in the box")

    var key := func(v: Vector3) -> Vector3i:
        return Vector3i(roundi(v.x * 16.0), roundi(v.y * 16.0), roundi(v.z * 16.0))
    var full_vset := {}
    for tri in full_core:
        for v in tri:
            full_vset[key.call(v)] = true
    var patch_vset := {}
    for tri in patch_core:
        for v in tri:
            patch_vset[key.call(v + shift)] = true
    var missing := 0
    for k in full_vset:
        if not patch_vset.has(k):
            missing += 1
    var extra := 0
    for k in patch_vset:
        if not full_vset.has(k):
            extra += 1
    gut.p("verts full∖patch=%d patch∖full=%d" % [missing, extra])
    assert_eq(missing, 0, "every full-build vertex in the box is reproduced by the sub-octree patch")
    assert_eq(extra,   0, "the sub-octree patch introduces no vertex absent from the full build")

    # F. Watertight: assemble (full − core) + (patch shifted to world); weld; no NEW boundary edges
    # vs the full build (no cracks at the seam), and manifold. Both audits are position-welded.
    var all_verts := PackedVector3Array()
    var all_idx   := PackedInt32Array()
    var full_idx: PackedInt32Array     = full[Mesh.ARRAY_INDEX]
    var full_verts: PackedVector3Array = full[Mesh.ARRAY_VERTEX]
    for v in full_verts:
        all_verts.append(v)
    for t in full_owners.size():
        var o: Vector3 = full_owners[t]
        if o.x >= core_min.x and o.x < core_max.x and o.y >= core_min.y and o.y < core_max.y and o.z >= core_min.z and o.z < core_max.z:
            continue
        all_idx.append(full_idx[t*3]); all_idx.append(full_idx[t*3+1]); all_idx.append(full_idx[t*3+2])
    if not patch.is_empty():
        var patch_verts: PackedVector3Array = patch[Mesh.ARRAY_VERTEX]
        var patch_idx:   PackedInt32Array   = patch[Mesh.ARRAY_INDEX]
        var base := all_verts.size()
        for v in patch_verts:
            all_verts.append(v + shift)
        for i in patch_idx.size():
            all_idx.append(patch_idx[i] + base)
    var spliced := _edge_audit_welded(all_verts, all_idx)
    var full_a  := _edge_audit_welded(full_verts, full_idx)
    gut.p("full welded boundary=%d  spliced boundary=%d nonmanifold=%d" % [
        full_a.boundary, spliced.boundary, spliced.nonmanifold])
    assert_eq(spliced.boundary,    full_a.boundary, "no NEW boundary edges (no cracks at the seam)")
    assert_eq(spliced.nonmanifold, 0,               "spliced mesh is manifold")
