extends GutTest

# Gate test for the multi-LOD splice. Validates that the build-box splice reproduces the full build
# across a LOD transition: a splice builds on the FULL build's frame (root_origin / DEPTH) restricted
# by a build-box to the edit region + apron, emitting only the core. Its cells therefore share the
# full build's lattice and neighbours, so the core triangles are reproduced EXACTLY and the seam
# can't crack. The full build is the oracle (the cache the live splice patches against).
#
# Field: an analytic 2-level sphere clipmap. Analytic is correct HERE because the oracle is the full
# build on the SAME field — this test isolates the build-box restriction + boundary stitching, not
# the field's fidelity (the real-terrain watertight guards live in test_dc_real_terrain.gd /
# test_dc_incremental_splice.gd). A finite HALF0 forces the sphere surface through the level-0/1
# boundary so coarse (collapsed) cells appear outside the fine core — the cells the splice must patch.

const SIZE   := 64
const DIM    := SIZE + 1                 # 65 samples per level per axis
const DEPTH  := 6                        # octree root [0,64]^3
const HALF0  := 12.0                     # level-0 half-extent; level-1 used at Chebyshev > 12
const CENTER := Vector3(32, 32, 32)
const RADIUS := 24.0                     # sphere surface crosses the LOD band
const TOL    := 2.0                      # screen-error threshold (px) the gate reasons about
# Camera far along +z with proj == distance, so proj/dist ~= 1 and the screen error we*proj/dist
# ~= the world residual we — the collapse is then driven by the field (a stable LOD transition the
# splice must reproduce), not by per-cell distance falloff. Full build and patch share these, so the
# crack-free gate stays an exact-reproduction check regardless of the absolute values.
const CAM    := Vector3(32, 32, 2032)
const PROJ   := 2000.0


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
        CENTER, HALF0, DEPTH, CAM, PROJ, TOL, true, Vector3i.ZERO)
    assert_false(arrays.is_empty(), "produced a surface")
    var owners := mesher.get_last_triangle_owners()
    var sizes  := mesher.get_last_triangle_owner_sizes()
    assert_eq(sizes.size(), owners.size(), "one size per triangle")
    for i in sizes.size():
        var s := int(sizes[i])
        assert_true(s > 0 and (s & (s - 1)) == 0, "size is power-of-two (tri %d = %d)" % [i, s])


# THE GATE TEST: a build-box splice reproduces the full build across a LOD transition.
# Necessity LOD made the old OFFSET sub-octree splice crack (its sub_origin frame stitched its
# artificial boundary differently than the full build — build/collapse/align were proven frame-pure,
# the divergence was purely emit-stage at the offset boundary). The fix is structural: a splice now
# builds on the FULL build's frame (root_origin / DEPTH), restricted by a build-box to the edit box +
# apron, emitting only the core. Its cells therefore share the full build's lattice AND neighbours, so
# the core triangles are reproduced EXACTLY and the seam can't crack — no sub_origin shift, no
# align_cell, no max_leaf cap, no shared collapse-set. This test drives that path.
func test_buildbox_splice_reproduces_full_build_across_lod() -> void:
    var clip := _clip()
    var world_origin := Vector3i.ZERO

    # A. Full build (the oracle).
    var mesher := DCOctreeMesher.new()
    var full := mesher.mesh_clipmap(clip.data, DIM, clip.origins, clip.cells,
        CENTER, HALF0, DEPTH, CAM, PROJ, TOL, true, world_origin)
    assert_false(full.is_empty(), "full build produced a surface")
    var full_owners := mesher.get_last_triangle_owners()
    var full_sizes  := mesher.get_last_triangle_owner_sizes()

    # B. Pick a core box around the coarsest interior owner (a LOD transition the splice must stitch).
    var seed_i := -1
    var seed_sz := 0
    for t in full_owners.size():
        var sz := int(full_sizes[t])
        var o: Vector3 = full_owners[t]
        var cheb := maxi(absi(int(o.x) - int(CENTER.x)), maxi(absi(int(o.y) - int(CENTER.y)), absi(int(o.z) - int(CENTER.z))))
        if sz > seed_sz and cheb > int(HALF0) and cheb < int(HALF0) * 2:
            seed_sz = sz
            seed_i = t
    assert_gt(seed_i, -1, "found an interior LOD-transition owner")
    var sc := Vector3i(full_owners[seed_i])
    var core_min := sc - Vector3i.ONE * (seed_sz * 2)
    var core_max := sc + Vector3i.ONE * (seed_sz * 3)
    var apron := Vector3i.ONE * 8        # ≥ the point-location stitch radius, so core cells' neighbours are full-res

    # C. The build-box splice: SAME frame as the full build, build only core+apron, emit only core.
    var patch := mesher.mesh_clipmap(clip.data, DIM, clip.origins, clip.cells,
        CENTER, HALF0, DEPTH, CAM, PROJ, TOL, true, world_origin,
        [], PackedColorArray(), false, 0.0,
        core_min, core_max,                          # emit box: only the core triangles
        core_min - apron, core_max + apron)          # build box: descend only here
    var patch_owners := mesher.get_last_triangle_owners()

    # D. Same frame → no shift. The patch's core triangles must equal the full build's, vertex-for-vertex.
    var full_core  := _tris_in_box(full,  full_owners,  core_min, core_max)
    var patch_core := _tris_in_box(patch, patch_owners, core_min, core_max)
    gut.p("full_core=%d patch_core=%d (core %s..%s, seed size %d)" % [
        full_core.size(), patch_core.size(), core_min, core_max, seed_sz])
    assert_gt(full_core.size(), 0, "full build has triangles in the core box")
    assert_eq(patch_core.size(), full_core.size(),
        "build-box splice reproduces the full build's triangle COUNT in the box")

    var key := func(v: Vector3) -> Vector3i:
        return Vector3i(roundi(v.x * 16.0), roundi(v.y * 16.0), roundi(v.z * 16.0))
    var full_vset := {}
    for tri in full_core:
        for v in tri:
            full_vset[key.call(v)] = true
    var patch_vset := {}
    for tri in patch_core:
        for v in tri:
            patch_vset[key.call(v)] = true
    var missing := 0
    for k in full_vset:
        if not patch_vset.has(k):
            missing += 1
    var extra := 0
    for k in patch_vset:
        if not full_vset.has(k):
            extra += 1
    gut.p("verts full∖patch=%d patch∖full=%d" % [missing, extra])
    assert_eq(missing, 0, "every full-build vertex in the box is reproduced by the build-box patch")
    assert_eq(extra,   0, "the build-box patch introduces no vertex absent from the full build")

    # E. Watertight: assemble (full − core) + patch core; weld; no NEW boundary edges vs the full
    # build (no cracks at the seam), and manifold. Both audits are position-welded.
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
            all_verts.append(v)
        for i in patch_idx.size():
            all_idx.append(patch_idx[i] + base)
    var spliced := _edge_audit_welded(all_verts, all_idx)
    var full_a  := _edge_audit_welded(full_verts, full_idx)
    gut.p("full welded boundary=%d  spliced boundary=%d nonmanifold=%d" % [
        full_a.boundary, spliced.boundary, spliced.nonmanifold])
    assert_eq(spliced.boundary,    full_a.boundary, "no NEW boundary edges (no cracks at the seam)")
    assert_eq(spliced.nonmanifold, 0,               "spliced mesh is manifold")
