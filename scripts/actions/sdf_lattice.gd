class_name SdfLattice
extends RefCounted

# The field an edit writes: a dense cube of float32 SDF values on the lattice of the leaves the
# write lands at, plus the world box whose overlapping leaves it rewrites. Every edit path builds
# one of these and hands THIS array to EditStore.write_region (write(), StoreWrite.cells) — the
# prediction is the write, not a model of it. write_region sets every leaf overlapping the box
# from the array's trilerp: leaves coarser than `cell` are subdivided first, leaves finer than it
# (an earlier finer edit) are written too, and a trilerp reproduces itself exactly on any sub-leaf.
# So a rewritten cell's post-edit value at its sample point IS this lattice trilerped there (to
# float32 rounding), whatever the store held before, and flips() is the brush TEST that matches
# the brush WRITE. The "before" side of flips() is the store's own sample, read before the write.
#
# (At the current RENDER_SUBDIV_LOG2 = 0 every writer lands on 1 m leaves: brush stamps and
# imprints at RENDER_BASE_CELL = 1 m, StoreWrite at 1 m. Nothing here depends on that.)

var origin:    Vector3               # world position of lattice point (0, 0, 0)
var cell:      float                 # lattice spacing = the leaf size the write lands at
var dim:       int                   # points per axis (a cube)
var sdf:       PackedFloat32Array    # dim^3 values, x fastest (write_region's layout)
var region_lo: Vector3               # leaves overlapping the open box (region_lo, region_hi)
var region_hi: Vector3               # are the ones the write rewrites
var writes:    bool = false          # some point differs from the store's current value there
                                     # (set by the builder, which reads both)


func _init(p_origin: Vector3, p_cell: float, p_dim: int, p_lo: Vector3, p_hi: Vector3) -> void:
    origin    = p_origin
    cell      = p_cell
    dim       = p_dim
    region_lo = p_lo
    region_hi = p_hi
    sdf.resize(dim * dim * dim)


func index(i: Vector3i) -> int:
    return i.x + dim * (i.y + dim * i.z)

func point(i: Vector3i) -> Vector3:
    return origin + Vector3(i) * cell


# Whether the write rewrites the leaves over coordinate `v` on `axis` (EditStore's strict-overlap
# test, which is separable per axis).
func _rewrites_1d(v: float, axis: int) -> bool:
    var leaf := floorf(v / cell) * cell
    return leaf < region_hi[axis] and leaf + cell > region_lo[axis]


# Post-write SDF at `p` (inside a rewritten leaf): the lattice trilerped, as the leaf will be.
func value_at(p: Vector3) -> float:
    var l  := (p - origin) / cell
    var i0 := Vector3i(floori(l.x), floori(l.y), floori(l.z))
    return _trilerp(i0, l - Vector3(i0))

# The leaf with lattice corner `i0`, trilerped at fractions `f` (each in [0, 1]) across it.
func _trilerp(i0: Vector3i, f: Vector3) -> float:
    var sy := dim
    var sz := dim * dim
    var i  := index(i0)
    var c00 := lerpf(sdf[i],           sdf[i + 1],           f.x)
    var c10 := lerpf(sdf[i + sy],      sdf[i + sy + 1],      f.x)
    var c01 := lerpf(sdf[i + sz],      sdf[i + sz + 1],      f.x)
    var c11 := lerpf(sdf[i + sy + sz], sdf[i + sy + sz + 1], f.x)
    return lerpf(lerpf(c00, c10, f.y), lerpf(c01, c11, f.y), f.z)


# Whether the write turns some point of `box` solid that the store holds as air now
# (solidifies_in) / air that it holds as solid now (empties_in) — the player-safety question,
# asked of the FIELD the write lays down, not of cell centres: a part or brush thinner than a
# cell can put real geometry in a box without flipping any cell's sample point.
#
# Over each rewritten leaf the written field is one trilerp, so over the leaf's intersection
# with `box` its minimum and maximum lie at that sub-box's corners: testing those corners finds
# every piece of `box` the write makes solid (air). The "before" side is read at the same points,
# plus every cell sample point inside the sub-box — so a flipped cell inside `box` is always seen
# (this subsumes the cell-flip test) and so is any sub-cell solid the write puts there.
func solidifies_in(store: EditStore, box: AABB) -> bool:
    return _turns_in(store, box, true)

func empties_in(store: EditStore, box: AABB) -> bool:
    return _turns_in(store, box, false)


func _turns_in(store: EditStore, box: AABB, to_solid: bool) -> bool:
    var pieces: Array = [_pieces_1d(box, 0), _pieces_1d(box, 1), _pieces_1d(box, 2)]
    var t := VoxelConstants.SDF_SOLID_THRESHOLD
    for pz: Array in pieces[2]:
        for py: Array in pieces[1]:
            for px: Array in pieces[0]:
                var i0 := Vector3i(px[0], py[0], pz[0])
                for fz: float in pz[1]:
                    for fy: float in py[1]:
                        for fx: float in px[1]:
                            var f   := Vector3(fx, fy, fz)
                            var now := _trilerp(i0, f)
                            if (now < t) != to_solid:
                                continue
                            var was := store.sample(origin + (Vector3(i0) + f) * cell)
                            if (was < t) != to_solid:
                                return true
    return false


# Along `axis`: for each rewritten leaf the box overlaps, [lattice index of the leaf's low corner,
# the fractions across that leaf to test — the overlap's two ends and any cell sample point
# between them].
func _pieces_1d(box: AABB, axis: int) -> Array:
    var lo: float = box.position[axis]
    var hi: float = lo + box.size[axis]
    var off: float = VoxelConstants.VOXEL_CENTER_OFFSET[axis]
    var out: Array = []
    for k in range(maxi(floori((lo - origin[axis]) / cell), 0), mini(ceili((hi - origin[axis]) / cell), dim - 1)):
        var leaf_lo: float = origin[axis] + float(k) * cell
        if not _rewrites_1d(leaf_lo + cell * 0.5, axis):
            continue
        var a := maxf(lo, leaf_lo)
        var b := minf(hi, leaf_lo + cell)
        var fracs: Array[float] = [(a - leaf_lo) / cell, (b - leaf_lo) / cell]
        for c in range(floori(a - off), ceili(b - off) + 1):
            var sp := float(c) + off
            if sp > a and sp < b:
                fracs.append((sp - leaf_lo) / cell)
        out.append([k, fracs])
    return out


# Every cell whose sample point sits in a rewritten leaf — the only cells the write can change.
func cells() -> Array[Vector3i]:
    var axes: Array = [[], [], []]
    for axis in 3:
        var off: float = VoxelConstants.VOXEL_CENTER_OFFSET[axis]
        for c in range(floori(region_lo[axis]) - 1, ceili(region_hi[axis]) + 1):
            if _rewrites_1d(float(c) + off, axis):
                axes[axis].append(c)
    var out: Array[Vector3i] = []
    for z: int in axes[2]:
        for y: int in axes[1]:
            for x: int in axes[0]:
                out.append(Vector3i(x, y, z))
    return out


# The cells this write will flip, predicted against the store's current field.
func flips(store: EditStore) -> CellFlips:
    var out := CellFlips.new()
    for c in cells():
        var p := VoxelUtils.sample_point(c)
        out._add(c, store.sample(p), value_at(p))
    return out


# Write the lattice into the store (every leaf in the region), with per-leaf `indices`
# (materials(), or empty for material 0).
func write(store: EditStore, indices: PackedByteArray) -> void:
    store.write_region(sdf, indices, dim, origin, cell)


# Per-leaf material for write(). A leaf holds solid iff one of its corners is solid (a trilerp's
# extremes are at its corners), so a leaf takes `material` iff the edit made one of its corners
# solid — the brush is solid there (`brush_solid(point)`), or the write turned an air point solid.
# `material` < 0 never repaints (a carve). Existing terrain the brush didn't make keeps its
# material, read at the leaf centre; a leaf left with no solid corner takes 0 unless `air_keeps`.
func materials(store: EditStore, material: int, brush_solid: Callable, air_keeps: bool) -> PackedByteArray:
    var made := PackedByteArray()   # per point: 1 = the edit made it solid
    made.resize(dim * dim * dim)
    if material >= 0:
        for z in dim:
            for y in dim:
                for x in dim:
                    var i := Vector3i(x, y, z)
                    var p := point(i)
                    var now := sdf[index(i)]
                    if now < VoxelConstants.SDF_SOLID_THRESHOLD and (brush_solid.call(p) \
                            or store.sample(p) >= VoxelConstants.SDF_SOLID_THRESHOLD):
                        made[index(i)] = 1
    var out := PackedByteArray()
    out.resize(dim * dim * dim)
    var half := Vector3.ONE * (cell * 0.5)
    for z in dim - 1:
        for y in dim - 1:
            for x in dim - 1:
                var i := Vector3i(x, y, z)
                var painted := false
                var solid   := false
                for k in 8:
                    var j := index(i + Vector3i(CubeGeometry.corner(k)))
                    painted = painted or made[j] == 1
                    solid   = solid or sdf[j] < VoxelConstants.SDF_SOLID_THRESHOLD
                if painted:
                    out[index(i)] = material
                elif solid or air_keeps:
                    out[index(i)] = store.material_at(point(i) + half)
    return out


# The field a sphere brush writes: every leaf overlapping the brush box (radius + one leaf of
# padding, as EditStore::stamp_sphere pads it) gets its corners set to the current field combined
# with the sphere SDF — min (UNION) / max(-) (SUBTRACT). The region is the whole lattice cube, so
# write() rewrites exactly the leaves cells() and flips() range over.
static func sphere_stamp(store: EditStore, center: Vector3, radius: float, op: int, min_leaf: float) -> SdfLattice:
    var pad := Vector3.ONE * (radius + min_leaf)
    var first := ((center - pad) / min_leaf).floor()
    var span  := ((center + pad) / min_leaf).ceil() - first
    var dim   := int(maxf(span.x, maxf(span.y, span.z))) + 1
    var lo    := first * min_leaf
    var lat := SdfLattice.new(lo, min_leaf, dim, lo, lo + Vector3.ONE * (float(dim - 1) * min_leaf))
    for z in lat.dim:
        for y in lat.dim:
            for x in lat.dim:
                var i := Vector3i(x, y, z)
                var p := lat.point(i)
                var before := store.sample(p)
                var brush  := p.distance_to(center) - radius
                var after  := minf(before, brush) if op == VoxelConstants.STORE_OP_UNION else maxf(before, -brush)
                lat.sdf[lat.index(i)] = after
                lat.writes = lat.writes or after != before
    return lat
