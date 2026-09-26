class_name StoreWrite
extends RefCounted

# Writes a set of per-grid-point SDF edits into the EditStore as ONE dense region.
#
# The store keeps per-leaf corner samples; a grid point is a corner shared by up to 8 leaves,
# so individual-cell writes are ambiguous. The correct primitive is a dense cube: fill the box
# from the CURRENT field (store.sample / material_at) so untouched points keep their value,
# overwrite the edited points, then write_region once. A 1-cell margin guarantees every edited
# leaf's 8 corners fall inside the written box.
#
# `work` is the actions' shared shape: an Array of entries whose [0] is the Vector3i lattice
# point and [1] is the new SDF. `material_of(entry) -> int` returns the material id for the leaf
# whose origin is that point, or < 0 to keep its current material (carves, or ops that don't
# repaint).
# Returns the world-space box whose leaves were rewritten (for the terrain_sdf_changed event).
#
# The grid points here are store LATTICE points (a leaf's corners), not cells: a cell's
# solidity is read at its sample point (VoxelUtils.sample_point), which a write moves through
# the trilerp of its 8 corners. lattice(work).flips(store) is what a work set does to cells.
static func cells(store: EditStore, work: Array, material_of: Callable) -> AABB:
    if work.is_empty():
        return AABB()
    var lat := lattice(store, work)
    var lo_cell := Vector3i(lat.origin)
    var indices := PackedByteArray()
    indices.resize(lat.dim * lat.dim * lat.dim)
    for z in lat.dim:
        for y in lat.dim:
            for x in lat.dim:
                var i := Vector3i(x, y, z)
                indices[lat.index(i)] = store.material_at(lat.point(i))
    for entry in work:
        var material: int = material_of.call(entry)
        if material >= 0:
            indices[lat.index(entry[0] - lo_cell)] = material
    lat.write(store, indices)
    return AABB(lat.region_lo, lat.region_hi - lat.region_lo)


# The field cells() will write for `work`: the current field over the work's box (plus the
# 1-cell margin), with the edited points overwritten.
static func lattice(store: EditStore, work: Array) -> SdfLattice:
    var lo_cell := _lo(work) - Vector3i.ONE
    var span    := _span(work)
    var dim     := maxi(span.x, maxi(span.y, span.z)) + 1
    var lat := SdfLattice.new(Vector3(lo_cell), 1.0, dim,
        Vector3(lo_cell), Vector3(lo_cell) + Vector3.ONE * float(dim - 1))
    for z in dim:
        for y in dim:
            for x in dim:
                var i := Vector3i(x, y, z)
                lat.sdf[lat.index(i)] = store.sample(lat.point(i))
    for entry in work:
        var i: int = lat.index(entry[0] - lo_cell)
        lat.writes = lat.writes or lat.sdf[i] != float(entry[1])
        lat.sdf[i] = entry[1]
    return lat


# Work that flips exactly one cell and no other, or [] when no write of its 8 lattice corners
# can (refuse, don't deform). The 1 m write rewrites the cell and its 26 neighbours, and each of
# those reads back the mean of its 8 corners (its centre, VoxelUtils.sample_point, trilerped) —
# of which it shares 4 / 2 / 1 with the target across a face / edge / vertex. So pushing the
# target's corners moves its neighbours too, and near the surface (where FillVoxel / EmptyVoxel
# are aimed) a naive push flips them. Instead solve for the corner offsets x_k, |x_k| <= z with
# z minimal, such that the target's mean lands CELL_EDIT_SDF past zero toward `solid` and every
# neighbour's post-write mean stays on its CURRENT side by CELL_KEEP_SDF (which also repairs a
# neighbour the rewrite alone would flip, where the corners allow).
static func one_cell(store: EditStore, cell: Vector3i, solid: bool) -> Array:
    var unchanged: Array = []
    for k in 8:
        var point := cell + Vector3i(CubeGeometry.corner(k))
        unchanged.append([point, store.sample(Vector3(point))])
    var base := lattice(store, unchanged)   # the field the rewrite alone leaves
    var lo   := cell - Vector3i.ONE
    var a: Array[PackedFloat64Array] = []
    var b := PackedFloat64Array()
    for o in base.cells():
        var mean := 0.0
        for i in 8:
            mean += base.sdf[base.index(o - lo + Vector3i(CubeGeometry.corner(i)))] / 8.0
        var want_solid := solid if o == cell else TerrainProbe.is_solid(store, o)
        var margin := VoxelConstants.CELL_EDIT_SDF if o == cell else VoxelConstants.CELL_KEEP_SDF
        # Row over y_k = x_k + z (so y_k in [0, 2z]) and z: sgn * (sum_S x_k) <= bound.
        var sgn := 1.0 if want_solid else -1.0
        var row := PackedFloat64Array()
        row.resize(9)
        for k in 8:
            var shared := (o - cell) - Vector3i(CubeGeometry.corner(k))   # each axis in {-1, 0} iff shared
            if shared.x <= 0 and shared.x >= -1 and shared.y <= 0 and shared.y >= -1 \
                    and shared.z <= 0 and shared.z >= -1:
                row[k] = sgn
                row[8] -= sgn
        a.append(row)
        b.append(-8.0 * (mean + margin) if want_solid else 8.0 * (mean - margin))
    for k in 8:
        var bound := PackedFloat64Array()
        bound.resize(9)
        bound[k] = 1.0
        bound[8] = -2.0
        a.append(bound)
        b.append(0.0)
    var cost := PackedFloat64Array()
    cost.resize(9)
    cost[8] = 1.0
    var y := Simplex.minimize(cost, a, b)
    if y.is_empty():
        return []
    var work: Array = []
    for k in 8:
        var point := cell + Vector3i(CubeGeometry.corner(k))
        work.append([point, base.sdf[base.index(point - lo)] + y[k] - y[8]])
    return work


static func _lo(work: Array) -> Vector3i:
    var lo: Vector3i = work[0][0]
    for entry in work:
        lo = lo.min(entry[0])
    return lo

# Extent of the work's box including the 1-cell margin on both sides.
static func _span(work: Array) -> Vector3i:
    var hi: Vector3i = work[0][0]
    for entry in work:
        hi = hi.max(entry[0])
    return hi - _lo(work) + Vector3i.ONE * 2
