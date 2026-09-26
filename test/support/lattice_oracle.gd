extends RefCounted

# The reference oracle for test_edit_store_predict: the GDScript lattice builders and lattice
# queries the game ran before they moved into EditStore (C++) — SdfLattice.sphere_stamp / flips /
# _turns_in, VoxelImprint.lattice, StoreWrite.lattice, BellSculptAction._compute_work,
# FlattenAction._compute_work and ConstructionAction._attached — kept verbatim so the
# byte-identical gate compares the C++ against an independent implementation rather than against
# itself. Nothing in the game calls this.
# (Drafted by Claude, overnight 2026-09-26; moved from scripts/actions/ unchanged but for the
# receiver: each former method takes its SdfLattice / store / action parameters explicitly. Since
# sdf-lattice-writes-false-change-at-max-faces the builders read "before" from the rewritten leaf
# that owns each point and compare at float32 — the originals' store.sample read the neighbouring
# leaf on the region's max faces.)


static func sphere_stamp(store: EditStore, center: Vector3, radius: float, op: int, min_leaf: float) -> SdfLattice:
    var pad := Vector3.ONE * (radius + min_leaf)
    var first := ((center - pad) / min_leaf).floor()
    var span  := ((center + pad) / min_leaf).ceil() - first
    var dim   := int(maxf(span.x, maxf(span.y, span.z))) + 1
    var lat := SdfLattice.new(first * min_leaf, min_leaf, dim)
    for z in lat.dim:
        for y in lat.dim:
            for x in lat.dim:
                var i := Vector3i(x, y, z)
                var p := lat.point(i)
                var before := store.sample_toward(p, _owner_centre(lat, i))
                var brush  := p.distance_to(center) - radius
                var after  := minf(before, brush) if op == VoxelConstants.STORE_OP_UNION else maxf(before, -brush)
                lat.sdf[lat.index(i)] = after
                lat.writes = lat.writes or lat.sdf[lat.index(i)] != _f32(before)
    return _settled(lat, store)


static func imprint(store: EditStore, shape: CsgShape, xform: Transform3D, op: int) -> SdfLattice:
    var inverse := xform.affine_inverse()
    var box := VoxelImprint.world_box(shape, xform)
    var cell := VoxelConstants.RENDER_BASE_CELL
    var lo := Vector3i((box.position / cell).floor()) - Vector3i.ONE
    var hi := Vector3i(((box.position + box.size) / cell).ceil()) + Vector3i.ONE
    var span := hi - lo
    var dim := maxi(span.x, maxi(span.y, span.z)) + 1
    var lat := SdfLattice.new(Vector3(lo) * cell, cell, dim)
    for z in dim:
        for y in dim:
            for x in dim:
                var i := Vector3i(x, y, z)
                var wp := lat.point(i)
                var dist := clampf(shape.sdf(inverse * wp), VoxelConstants.SDF_SOLID, VoxelConstants.SDF_AIR)
                var existing := store.sample_toward(wp, _owner_centre(lat, i))
                var combined := minf(existing, dist) if op == CsgState.Op.ADD else maxf(existing, -dist)
                lat.sdf[lat.index(i)] = combined
                lat.writes = lat.writes or lat.sdf[lat.index(i)] != _f32(existing)
    return _settled(lat, store)


static func work(store: EditStore, edits: Array[LatticeEdit]) -> SdfLattice:
    var lo_cell := _lo(edits) - Vector3i.ONE
    var span    := _span(edits)
    var dim     := maxi(span.x, maxi(span.y, span.z)) + 1
    var lat := SdfLattice.new(Vector3(lo_cell), 1.0, dim)
    for z in dim:
        for y in dim:
            for x in dim:
                var i := Vector3i(x, y, z)
                lat.sdf[lat.index(i)] = store.sample_toward(lat.point(i), _owner_centre(lat, i))
    for edit in edits:
        var i := lat.index(edit.point - lo_cell)
        lat.writes = lat.writes or lat.sdf[i] != _f32(edit.sdf)
        lat.sdf[i] = edit.sdf
    return _settled(lat, store)


# The rewritten leaf a point's "before" is read from: the one above it, but below it on a max face.
static func _owner_centre(lat: SdfLattice, i: Vector3i) -> Vector3:
    var top := lat.dim - 2
    return lat.origin + (Vector3(mini(i.x, top), mini(i.y, top), mini(i.z, top)) + Vector3.ONE * 0.5) * lat.cell


# The float32 a lattice stores for `v`.
static func _f32(v: float) -> float:
    return PackedFloat32Array([v])[0]


# Points that all match the leaf they were read from can still change another rewritten leaf's
# corner; that part of the question is EditStore's own dry run of the write (not re-derived here:
# it needs the tree), tested directly in test_lattice_writes. So when no point changes, the gate's
# `writes` is the C++ answer, not an independent one.
static func _settled(lat: SdfLattice, store: EditStore) -> SdfLattice:
    lat.writes = lat.writes or store.lattice_writes(lat.sdf, lat.dim, lat.origin, lat.cell)
    return lat


static func _lo(edits: Array[LatticeEdit]) -> Vector3i:
    var lo := edits[0].point
    for edit in edits:
        lo = lo.min(edit.point)
    return lo

static func _span(edits: Array[LatticeEdit]) -> Vector3i:
    var hi := edits[0].point
    for edit in edits:
        hi = hi.max(edit.point)
    return hi - _lo(edits) + Vector3i.ONE * 2


static func flips(lat: SdfLattice, store: EditStore) -> CellFlips:
    var out := CellFlips.new()
    for c in lat.cells():
        var p := VoxelUtils.sample_point(c)
        out._add(c, store.sample(p), _value_at(lat, p))
    return out


static func _value_at(lat: SdfLattice, p: Vector3) -> float:
    var l  := (p - lat.origin) / lat.cell
    var i0 := Vector3i(floori(l.x), floori(l.y), floori(l.z))
    return _trilerp(lat, i0, l - Vector3(i0))

static func _trilerp(lat: SdfLattice, i0: Vector3i, f: Vector3) -> float:
    var sy := lat.dim
    var sz := lat.dim * lat.dim
    var i  := lat.index(i0)
    var sdf := lat.sdf
    var c00 := lerpf(sdf[i],           sdf[i + 1],           f.x)
    var c10 := lerpf(sdf[i + sy],      sdf[i + sy + 1],      f.x)
    var c01 := lerpf(sdf[i + sz],      sdf[i + sz + 1],      f.x)
    var c11 := lerpf(sdf[i + sy + sz], sdf[i + sy + sz + 1], f.x)
    return lerpf(lerpf(c00, c10, f.y), lerpf(c01, c11, f.y), f.z)


static func turns_in(lat: SdfLattice, store: EditStore, box: AABB, to_solid: bool) -> bool:
    var pieces: Array = [_pieces_1d(lat, box, 0), _pieces_1d(lat, box, 1), _pieces_1d(lat, box, 2)]
    var t := VoxelConstants.SDF_SOLID_THRESHOLD
    for pz: Array in pieces[2]:
        for py: Array in pieces[1]:
            for px: Array in pieces[0]:
                var i0 := Vector3i(px[0], py[0], pz[0])
                for fz: float in pz[1]:
                    for fy: float in py[1]:
                        for fx: float in px[1]:
                            var f   := Vector3(fx, fy, fz)
                            var now := _trilerp(lat, i0, f)
                            if (now < t) != to_solid:
                                continue
                            var was := store.sample(lat.origin + (Vector3(i0) + f) * lat.cell)
                            if (was < t) != to_solid:
                                return true
    return false


static func _rewrites_1d(lat: SdfLattice, v: float, axis: int) -> bool:
    var leaf := floorf(v / lat.cell) * lat.cell
    return leaf < lat.region_hi[axis] and leaf + lat.cell > lat.region_lo[axis]

static func _pieces_1d(lat: SdfLattice, box: AABB, axis: int) -> Array:
    var lo: float = box.position[axis]
    var hi: float = lo + box.size[axis]
    var off: float = VoxelConstants.VOXEL_CENTER_OFFSET[axis]
    var out: Array = []
    for k in range(maxi(floori((lo - lat.origin[axis]) / lat.cell), 0),
            mini(ceili((hi - lat.origin[axis]) / lat.cell), lat.dim - 1)):
        var leaf_lo: float = lat.origin[axis] + float(k) * lat.cell
        if not _rewrites_1d(lat, leaf_lo + lat.cell * 0.5, axis):
            continue
        var a := maxf(lo, leaf_lo)
        var b := minf(hi, leaf_lo + lat.cell)
        var fracs: Array[float] = [(a - leaf_lo) / lat.cell, (b - leaf_lo) / lat.cell]
        for c in range(floori(a - off), ceili(b - off) + 1):
            var sp := float(c) + off
            if sp > a and sp < b:
                fracs.append((sp - leaf_lo) / lat.cell)
        out.append([k, fracs])
    return out


# ConstructionAction._attached: `lat` is the part's imprint lattice, `shape` / `xform` its brush.
static func attached(store: EditStore, lat: SdfLattice, shape: CsgShape, xform: Transform3D) -> bool:
    var inverse := xform.affine_inverse()
    var reach   := lat.cell * sqrt(3.0) * 0.5
    var down    := Vector3.DOWN * VoxelConstants.VOXEL_SIZE
    for z in lat.dim:
        for y in lat.dim:
            for x in lat.dim:
                var p := lat.point(Vector3i(x, y, z))
                if shape.sdf(inverse * p) > reach:
                    continue
                if store.sample(p) < VoxelConstants.SDF_SOLID_THRESHOLD \
                        or store.sample(p + down) < VoxelConstants.SDF_SOLID_THRESHOLD:
                    return true
    return false


# BellSculptAction._compute_work; `sign` is -1 for raise, +1 for lower.
static func bell_work(store: EditStore, position: Vector3, radius: float, sign: float) -> Array[LatticeEdit]:
    var amplitude := radius * BellSculptAction.AMPLITUDE_RATIO
    var origin    := position - Vector3.ONE * radius
    var dims      := Vector3.ONE * (radius * 2.0)
    var r2        := radius * radius
    var out: Array[LatticeEdit] = []
    VoxelUtils.for_each_in_bounding_box(origin, dims, func(point: Vector3i) -> void:
        var dx := float(point.x) - position.x
        var dz := float(point.z) - position.z
        var d2 := dx * dx + dz * dz
        if d2 >= r2:
            return
        var t       := d2 / r2
        var falloff := (1.0 - t) * (1.0 - t)
        var bell    := amplitude * falloff
        out.append(LatticeEdit.new(point, store.sample(Vector3(point)) + sign * bell))
    )
    return out


# FlattenAction._compute_work; `normal` is unit length.
static func flatten_work(store: EditStore, plane_point: Vector3, normal: Vector3, radius: float) -> Array[LatticeEdit]:
    var origin := plane_point - Vector3.ONE *  radius
    var dims   :=                Vector3.ONE * (radius * 2.0)
    var columns: Dictionary = {}
    VoxelUtils.for_each_in_bounding_box(origin, dims, func(pos: Vector3i) -> void:
        var plane_dist: float = normal.dot(Vector3(pos) - plane_point)
        if absf(plane_dist) > radius:
            return
        var lateral := Vector3(pos) - normal * plane_dist
        var key     := Vector3i(roundi(lateral.x), roundi(lateral.y), roundi(lateral.z))
        if not columns.has(key):
            columns[key] = _Column.new()
        columns[key].add(pos, plane_dist, store.sample(Vector3(pos)) < VoxelConstants.SDF_SOLID_THRESHOLD)
    )
    var out: Array[LatticeEdit] = []
    for column: _Column in columns.values():
        for c: _Candidate in column.candidates:
            if c.edit.sdf > 0.0 and column.pos_has_air and c.was_solid:
                out.append(c.edit)
            elif c.edit.sdf < 0.0 and column.neg_has_solid and not c.was_solid:
                out.append(c.edit)
    return out


class _Column:
    var candidates: Array[_Candidate] = []
    var pos_has_air   := false
    var neg_has_solid := false

    func add(point: Vector3i, plane_dist: float, is_solid: bool) -> void:
        candidates.append(_Candidate.new(LatticeEdit.new(point, plane_dist), is_solid))
        pos_has_air   = pos_has_air   or (plane_dist > 0.0 and not is_solid)
        neg_has_solid = neg_has_solid or (plane_dist < 0.0 and is_solid)


class _Candidate:
    var edit:      LatticeEdit
    var was_solid: bool

    func _init(p_edit: LatticeEdit, p_was_solid: bool) -> void:
        edit      = p_edit
        was_solid = p_was_solid
