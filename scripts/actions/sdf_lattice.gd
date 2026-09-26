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
# The builders and the flips / safety queries run in EditStore (C++, predict_* and lattice_*),
# because a preview asks them every frame; this class carries the result.
#
# (At the current RENDER_SUBDIV_LOG2 = 0 every writer lands on 1 m leaves: brush stamps and
# imprints at RENDER_BASE_CELL = 1 m, StoreWrite at 1 m. Nothing here depends on that.)

var origin:    Vector3               # world position of lattice point (0, 0, 0)
var cell:      float                 # lattice spacing = the leaf size the write lands at
var dim:       int                   # points per axis (a cube)
var sdf:       PackedFloat32Array    # dim^3 values, x fastest (write_region's layout)
var made:      PackedByteArray       # per point, 1 = the write made it solid; set with `sdf` by
                                     # the brush builders (sphere_stamp, VoxelImprint.lattice) and
                                     # true only of that sdf; materials() reads it
var region_lo: Vector3               # leaves overlapping the open box (region_lo, region_hi)
var region_hi: Vector3               # are the ones the write rewrites: the whole cube
var writes:    bool = false          # the write changes some stored leaf corner's SDF (set by
                                     # the builder: EditStore.predict_*; material not considered)


func _init(p_origin: Vector3, p_cell: float, p_dim: int) -> void:
    origin    = p_origin
    cell      = p_cell
    dim       = p_dim
    region_lo = origin
    region_hi = origin + Vector3.ONE * (float(dim - 1) * cell)
    sdf.resize(dim * dim * dim)


# The lattice an EditStore.predict_* call returns, or null for its refusal (an empty Dictionary).
static func predicted(d: Dictionary) -> SdfLattice:
    if d.is_empty():
        return null
    var lat := SdfLattice.new(d.origin, d.cell, d.dim)
    lat.sdf    = d.sdf
    lat.made   = d.made
    lat.writes = d.writes
    return lat


func index(i: Vector3i) -> int:
    return i.x + dim * (i.y + dim * i.z)

func point(i: Vector3i) -> Vector3:
    return origin + Vector3(i) * cell


# The centre of the rewritten leaf a point's "before" value is read from (store.sample_toward): the
# one above it on each axis, as store.sample reads, except on a max face, where the leaf above is
# not rewritten. The C++ builders' Lattice::owner_centre (edit_store_lattice.h) is the same rule.
func owner_centre(i: Vector3i) -> Vector3:
    var top := dim - 2
    return origin + (Vector3(mini(i.x, top), mini(i.y, top), mini(i.z, top)) + Vector3.ONE * 0.5) * cell


# Whether the write rewrites the leaves over coordinate `v` on `axis` (EditStore's strict-overlap
# test, which is separable per axis).
func _rewrites_1d(v: float, axis: int) -> bool:
    var leaf := floorf(v / cell) * cell
    return leaf < region_hi[axis] and leaf + cell > region_lo[axis]


# Post-write SDF at `p` (inside a rewritten leaf): the lattice trilerped, as the leaf will be.
func value_at(p: Vector3) -> float:
    var l  := (p - origin) / cell
    var i0 := Vector3i(floori(l.x), floori(l.y), floori(l.z))
    var f  := l - Vector3(i0)
    var i  := index(i0)
    var sy := dim
    var sz := dim * dim
    var c00 := lerpf(sdf[i],           sdf[i + 1],           f.x)
    var c10 := lerpf(sdf[i + sy],      sdf[i + sy + 1],      f.x)
    var c01 := lerpf(sdf[i + sz],      sdf[i + sz + 1],      f.x)
    var c11 := lerpf(sdf[i + sy + sz], sdf[i + sy + sz + 1], f.x)
    return lerpf(lerpf(c00, c10, f.y), lerpf(c01, c11, f.y), f.z)


# Whether the write turns some point of `box` solid that the store holds as air now
# (solidifies_in) / air that it holds as solid now (empties_in) — the player-safety question,
# asked of the FIELD the write lays down, not of cell centres: a part or brush thinner than a
# cell can put real geometry in a box without flipping any cell's sample point. Over each
# rewritten leaf the written field is one trilerp, so its extremes over the leaf's piece of `box`
# lie at the piece's corners; EditStore.lattice_turns_in tests those, plus every cell sample point
# inside the piece (so a flipped cell inside `box` is always seen).
func solidifies_in(store: EditStore, box: AABB) -> bool:
    return store.lattice_turns_in(sdf, dim, origin, cell, box, true)

func empties_in(store: EditStore, box: AABB) -> bool:
    return store.lattice_turns_in(sdf, dim, origin, cell, box, false)


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


# The cells this write will flip, predicted against the store's current field. None when EditStore
# refuses the lattice (an empty Dictionary, with its error).
func flips(store: EditStore) -> CellFlips:
    var d   := store.lattice_flips(sdf, dim, origin, cell)
    var out := CellFlips.new()
    if d.is_empty():
        return out

    out.solid = d.solid
    out.air   = d.air
    return out


# Write the lattice into the store (every leaf in the region), with per-leaf `indices`
# (materials(), or empty: leaves keep the material they hold, 0 for one newly materialised).
# Returns the cells it flipped, MEASURED: each cells() member's sample read just before and just
# after the write (EditStore.write_region_flips), with what each emptied cell was made of. None,
# and nothing written, when EditStore refuses the lattice.
func write(store: EditStore, indices: PackedByteArray) -> CellFlips:
    var d   := store.write_region_flips(sdf, indices, dim, origin, cell)
    var out := CellFlips.new()
    if d.is_empty():
        return out

    out.solid         = d.solid
    out.air           = d.air
    out.air_materials = d.air_materials
    out.changed       = d.changed
    return out


# Per-leaf material for write(). A leaf holds solid iff one of its corners is solid (a trilerp's
# extremes are at its corners), so a leaf takes `material` iff the edit made one of its corners
# solid: `made`, which the brush builder records — the brush is solid there, or the write turned an
# air point solid (air as the owner leaf held it, the value the builder combined with; at a seam on
# a max face the leaf beyond can disagree). So this answers for the store as the builder read it.
# `material` < 0 never repaints (a carve). Existing terrain the brush didn't make keeps its
# material, read at the leaf centre; a leaf left with no solid corner takes 0 unless `air_keeps`.
# Runs in EditStore (lattice_materials); test_lattice_materials_predict gates it against the
# GDScript original (test/support/lattice_oracle.gd).
func materials(store: EditStore, material: int, air_keeps: bool) -> PackedByteArray:
    return store.lattice_materials(sdf, made, dim, origin, cell, material, air_keeps)


# The field a sphere brush writes: every leaf overlapping the brush box (radius + one leaf of
# padding, as EditStore::stamp_sphere pads it) gets its corners set to the current field combined
# with the sphere SDF — min (UNION) / max(-) (SUBTRACT). The region is the whole lattice cube, so
# write() rewrites exactly the leaves cells() and flips() range over.
static func sphere_stamp(store: EditStore, center: Vector3, radius: float, op: int, min_leaf: float) -> SdfLattice:
    return predicted(store.predict_sphere_stamp(center, radius, op, min_leaf))
