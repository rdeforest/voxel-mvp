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


# Two independent LOD meshes don't align at the shared face — the seam cracks.
# This is inherent (off-grid DC vertices), and the reason the transition band
# exists.
func test_raw_seam_cracks_without_a_band() -> void:
    var fine   := DualContour.build_mesh(_sphere, Vector3i(SEAM, 16, 16), Vector3.ZERO, 1.0)
    var coarse := DualContour.build_mesh(_sphere, Vector3i(SEAM / 2, 8, 8), Vector3(SEAM, 0, 0), 2.0)
    var a := _audit([fine, coarse])
    gut.p("raw seam (no band): boundary=%d nonmanifold=%d" % [a["boundary"], a["nonmanifold"]])
    assert_gt(a["boundary"], 0, "raw LOD seam must crack (the band's reason to exist)")

# The additive band zippers the fine open loop to the coarse open loop. Welded
# with both block meshes, the seam must have zero boundary edges.
func test_band_closes_the_seam() -> void:
    var fine   := DualContour.build_mesh(_sphere, Vector3i(SEAM, 16, 16), Vector3.ZERO, 1.0)
    var coarse := DualContour.build_mesh(_sphere, Vector3i(SEAM / 2, 8, 8), Vector3(SEAM, 0, 0), 2.0)
    var fv: PackedVector3Array = fine.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var fi: PackedInt32Array   = fine.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
    var cv: PackedVector3Array = coarse.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var ci: PackedInt32Array   = coarse.surface_get_arrays(0)[Mesh.ARRAY_INDEX]

    var floops := DcSeam.open_loops(fi)
    var cloops := DcSeam.open_loops(ci)
    gut.p("loops: fine=%d coarse=%d" % [floops.size(), cloops.size()])
    assert_eq(floops.size(), 1, "sphere meets the seam in one fine loop")
    assert_eq(cloops.size(), 1, "sphere meets the seam in one coarse loop")

    var band := DcSeam.stitch(_loop_pos(fv, floops[0]), _loop_pos(cv, cloops[0]))
    var a := _audit([fine, _band_mesh(band), coarse])
    gut.p("with band: boundary=%d nonmanifold=%d" % [a["boundary"], a["nonmanifold"]])
    assert_eq(a["boundary"], 0, "transition band must close the seam (no boundary edges)")

# In the engine the fine block can't see the whole coarse neighbour — only a few
# voxels past the face (its padding). This checks how deep a coarse slab must be
# meshed to reproduce the neighbour's seam loop EXACTLY (same vertices). That
# depth sets MAX_PADDING for the C++ port: depth d coarse cells -> need samples to
# fine-x bs + 2d, plus a gradient step -> MAX_PADDING ~= 2d + 2.
func test_coarse_slab_depth_reproduces_seam_loop() -> void:
    var full := DualContour.build_mesh(_sphere, Vector3i(SEAM / 2, 8, 8), Vector3(SEAM, 0, 0), 2.0)
    var full_loop := _min_x_loop(full)
    var matched := {}
    for d in [1, 2, 3]:
        var slab := DualContour.build_mesh(_sphere, Vector3i(d, 8, 8), Vector3(SEAM, 0, 0), 2.0)
        var slab_loop := _min_x_loop(slab)
        matched[d] = _same_positions(slab_loop, full_loop)
        gut.p("coarse slab depth %d: seam loop matches full=%s (slab n=%d, full n=%d)" % [
            d, matched[d], slab_loop.size(), full_loop.size()])
    assert_true(matched.get(1, false) or matched.get(2, false),
        "a shallow coarse slab must reproduce the neighbour's seam loop")

func _min_x_loop(mesh: ArrayMesh) -> PackedVector3Array:
    var v: PackedVector3Array   = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array   = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
    var best := PackedVector3Array()
    var best_x := INF
    for loop in DcSeam.open_loops(idx):
        var pos := _loop_pos(v, loop)
        var ax := 0.0
        for p in pos:
            ax += p.x
        ax /= maxf(1.0, pos.size())
        if ax < best_x:
            best_x = ax
            best = pos
    return best

func _same_positions(a: PackedVector3Array, b: PackedVector3Array) -> bool:
    if a.size() != b.size() or a.size() == 0:
        return false
    var sa: Array = []
    var sb: Array = []
    for p in a:
        sa.append(p.snapped(Vector3.ONE * 1e-3))
    for p in b:
        sb.append(p.snapped(Vector3.ONE * 1e-3))
    sa.sort()
    sb.sort()
    return sa == sb

func _loop_pos(verts: PackedVector3Array, loop: PackedInt32Array) -> PackedVector3Array:
    var out := PackedVector3Array()
    for idx in loop:
        out.append(verts[idx])
    return out

func _band_mesh(band: Dictionary) -> ArrayMesh:
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = band["verts"]
    arrays[Mesh.ARRAY_INDEX]  = band["indices"]
    var m := ArrayMesh.new()
    m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return m
