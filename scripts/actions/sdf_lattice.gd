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
    var x0 := floori(l.x)
    var y0 := floori(l.y)
    var z0 := floori(l.z)
    var fx := l.x - x0
    var fy := l.y - y0
    var fz := l.z - z0
    var sy := dim
    var sz := dim * dim
    var i  := x0 + sy * y0 + sz * z0
    var c00 := lerpf(sdf[i],           sdf[i + 1],           fx)
    var c10 := lerpf(sdf[i + sy],      sdf[i + sy + 1],      fx)
    var c01 := lerpf(sdf[i + sz],      sdf[i + sz + 1],      fx)
    var c11 := lerpf(sdf[i + sy + sz], sdf[i + sy + sz + 1], fx)
    return lerpf(lerpf(c00, c10, fy), lerpf(c01, c11, fy), fz)


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
