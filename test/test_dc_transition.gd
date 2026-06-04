extends GutTest

# Bite F2 (LOD seams): a fine-resolution block beside a coarse-resolution block
# of the SAME field cracks along the shared face, because Dual Contouring places
# off-grid QEF vertices that don't line up across resolutions. This suite first
# reproduces that crack as boundary edges at the seam, then (once the transition
# band exists) drives it to zero — the same reproduce-then-fix loop that fixed
# the back-facing holes.
#
# Setup: one sphere, fully inside the combined box, straddling the x = SEAM plane.
# Fine block meshes x in [0, SEAM] at cell 1; coarse block meshes x in [SEAM, 2*SEAM]
# at cell 2. The only place the welded mesh can have boundary edges is the seam.

const SEAM   := 8
const CENTER := Vector3(8, 8, 8)
const RADIUS := 6.0

var _sphere := func(p: Vector3) -> float: return p.distance_to(CENTER) - RADIUS


# --- welded watertightness audit (by position, so it's blind to index splits) ---

func _audit(meshes: Array) -> Dictionary:
    var pos_id := {}
    var edge_count := {}
    var tris := 0
    for m in meshes:
        var arrays: Array = m.surface_get_arrays(0)
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var idx: PackedInt32Array     = arrays[Mesh.ARRAY_INDEX]
        var local := PackedInt32Array()
        local.resize(verts.size())
        for i in verts.size():
            var key := verts[i].snapped(Vector3.ONE * 1e-3)
            if not pos_id.has(key):
                pos_id[key] = pos_id.size()
            local[i] = pos_id[key]
        for i in range(0, idx.size(), 3):
            tris += 1
            var w := [local[idx[i]], local[idx[i + 1]], local[idx[i + 2]]]
            for e in [[w[0], w[1]], [w[1], w[2]], [w[2], w[0]]]:
                var k := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
                edge_count[k] = edge_count.get(k, 0) + 1
    var boundary := 0
    var nonmanifold := 0
    for k in edge_count:
        if   edge_count[k] == 1: boundary += 1
        elif edge_count[k] >  2: nonmanifold += 1
    return {"boundary": boundary, "nonmanifold": nonmanifold, "tris": tris}


# A single uniform block is watertight on its own (sanity check on the harness).
func test_single_block_watertight():
    var m := DualContour.build_mesh(_sphere, Vector3i(16, 16, 16), Vector3.ZERO, 1.0)
    var a := _audit([m])
    assert_eq(a["boundary"], 0, "single block has no boundary edges")


# Baseline for the F2 transition band: a fine block beside a coarse block of the
# same field cracks at the shared face. Reported, not asserted — once the additive
# transition band lands, this test gains the fine+band+coarse meshes and asserts
# boundary == 0 (the band must drive the seam watertight).
func test_fine_coarse_seam_is_the_f2_target():
    var fine   := DualContour.build_mesh(_sphere, Vector3i(SEAM, 16, 16), Vector3.ZERO, 1.0)
    var coarse := DualContour.build_mesh(_sphere, Vector3i(SEAM / 2, 8, 8), Vector3(SEAM, 0, 0), 2.0)
    var a := _audit([fine, coarse])
    gut.p("LOD seam baseline (no band): boundary=%d nonmanifold=%d tris=%d" % [a["boundary"], a["nonmanifold"], a["tris"]])
    pending("F2: transition band not implemented yet; seam cracks (boundary=%d). Target: 0." % a["boundary"])
