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
# `work` is the lattice writers' shared currency: LatticeEdit records (point, new SDF, and the
# material of the leaf whose origin is that point, < 0 to keep its current one).
# cells() and write() return the cells the write flipped, measured across it (SdfLattice.write).
#
# The grid points here are store LATTICE points (a leaf's corners), not cells: a cell's
# solidity is read at its sample point (VoxelUtils.sample_point), which a write moves through
# the trilerp of its 8 corners. lattice(work).flips(store) is what a work set does to cells.
static func cells(store: EditStore, work: Array[LatticeEdit]) -> CellFlips:
    if work.is_empty():
        return CellFlips.new()
    return write(store, lattice(store, work), work)


# Write `lat`, which must be lattice(store, work) built against the store as it is now, with the
# work's materials. For a caller that measures or previews the field before writing it: handing
# over the lattice it measured makes the write that field, not a rebuild of it. The caller's
# terrain_sdf_changed box is the lattice's region.
static func write(store: EditStore, lat: SdfLattice, work: Array[LatticeEdit]) -> CellFlips:
    var indices := _current_materials(store, lat)
    if indices.is_empty():
        return CellFlips.new()

    var lo_cell := Vector3i(lat.origin)
    for edit in work:
        if edit.material >= 0:
            indices[lat.index(edit.point - lo_cell)] = edit.material
    return lat.write(store, indices)


# Write a work lattice (a work set's field, as lattice() or EditStore.predict_bell / predict_flatten
# build it) keeping every leaf's current material. Returns the rewritten box.
static func reshape(store: EditStore, lat: SdfLattice) -> AABB:
    var indices := _current_materials(store, lat)
    if indices.is_empty():
        return AABB()

    lat.write(store, indices)
    return AABB(lat.region_lo, lat.region_hi - lat.region_lo)


# Every lattice point's current material, or empty (with an error) for a lattice whose origin is
# not a whole number of cells. fill_indices_region reads (lo + i) * cell, which is lat.point(i)
# only on that grid; every EditStore.predict_* lattice is on it (integer origin, 1 m cell). Off
# it the bulk read would give the whole box its neighbours' materials, and an assert would not
# stop that in a release build.
static func _current_materials(store: EditStore, lat: SdfLattice) -> PackedByteArray:
    var lo := Vector3i((lat.origin / lat.cell).round())
    if Vector3(lo) * lat.cell != lat.origin:
        push_error("StoreWrite: lattice origin %s is not a whole number of %s m cells; write refused"
            % [lat.origin, lat.cell])
        return PackedByteArray()

    return store.fill_indices_region(lo, lat.dim, lat.cell)


# The field cells() will write for `work`: the current field over the work's box (plus the
# 1-cell margin), with the edited points overwritten. Built by EditStore.predict_work.
static func lattice(store: EditStore, work: Array[LatticeEdit]) -> SdfLattice:
    var points: Array[Vector3i] = []
    var sdfs := PackedFloat64Array()
    for edit in work:
        points.append(edit.point)
        sdfs.append(edit.sdf)
    return SdfLattice.predicted(store.predict_work(points, sdfs))


# Work that flips exactly one cell and no other, or [] when no write of its 8 lattice corners
# can (refuse, don't deform). The target leaf takes `material` (< 0 keeps its current one).
# The 1 m write rewrites the cell and its 26 neighbours, and each of
# those reads back the mean of its 8 corners (its centre, VoxelUtils.sample_point, trilerped) —
# of which it shares 4 / 2 / 1 with the target across a face / edge / vertex. So pushing the
# target's corners moves its neighbours too, and near the surface (where FillVoxel / EmptyVoxel
# are aimed) a naive push flips them. Instead solve for the corner offsets x_k, |x_k| <= z with
# z minimal, such that the target's mean lands CELL_EDIT_SDF past zero toward `solid` and every
# neighbour's post-write mean stays on its CURRENT side by CELL_KEEP_SDF (which also repairs a
# neighbour the rewrite alone would flip, where the corners allow).
static func one_cell(store: EditStore, cell: Vector3i, solid: bool, material: int = -1) -> Array[LatticeEdit]:
    var unchanged: Array[LatticeEdit] = []
    for k in 8:
        var point := cell + Vector3i(CubeGeometry.corner(k))
        unchanged.append(LatticeEdit.new(point, store.sample(Vector3(point))))
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
    var work: Array[LatticeEdit] = []
    if y.is_empty():
        return work
    for k in 8:
        var point := cell + Vector3i(CubeGeometry.corner(k))
        work.append(LatticeEdit.new(point, base.sdf[base.index(point - lo)] + y[k] - y[8],
            material if point == cell else -1))
    return work
