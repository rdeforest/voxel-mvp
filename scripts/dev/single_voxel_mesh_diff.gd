extends RefCounted

# What the production render (DCOctreeMesher.mesh_world, set up as DcWorldPreview does) draws
# around one cell, reduced to an inside/outside occupancy grid so two meshes can be diffed as
# volume. Occupancy is ray parity along +y per column: every column crosses the mesh an odd number
# of times above a point iff the point is under the surface. Column positions carry an irrational
# jitter so no ray runs exactly through a shared triangle edge. Used by probe_single_voxel.gd
# (https://github.com/rdeforest/voxel-mvp/issues/22, Characterization).

const DEPTH     := 13          # DcWorldPreview.DEPTH
const ROOT_SNAP := 64          # DcWorldPreview.ROOT_SNAP
const WIN       := 16          # window half-extent (m) — covers the region's columns to their top
const EPS_LIVE  := 0.5         # DcWorldPreview.EPS_MIN: where the controller settles with headroom
const REACH     := 2           # region = target cell +- REACH cells
const H         := 0.1         # occupancy grid pitch (m)
const JITTER    := Vector2(0.00731, 0.00417)
const SAME_VERT := 1e-4

# DcWorldPreview._view_proj for a 75° FOV on a 1080-line fullscreen viewport.
static var PROJ := 1080.0 / (2.0 * tan(deg_to_rad(75.0) * 0.5))

var region:  AABB
var n:       int                          # grid points per axis
var inside:  PackedByteArray              # n^3, x fastest
var tops:    Array[PackedFloat32Array]    # per column, sorted crossing heights
var verts:   PackedVector3Array           # world-space vertices inside the region
var colors:  PackedColorArray
var far:     PackedVector3Array           # world-space vertices in the window, outside the region
var capped:  int                          # columns whose field is solid at the window top


static func of(store: EditStore, cell: Vector3i, camera: Vector3, dense: bool) -> RefCounted:
    var out: RefCounted = load("res://scripts/dev/single_voxel_mesh_diff.gd").new()
    out.region = AABB(Vector3(cell - Vector3i.ONE * REACH), Vector3.ONE * float(2 * REACH + 1))
    out.n      = int(round(out.region.size.x / H))
    out._build(_mesh(store, cell, camera, dense))
    out.capped = out._capped(store, float(cell.y + WIN) - 0.5)
    return out


# The window's top face is open (DC's resident rim), so +y parity inverts in any column whose
# field is still solid there; a nonzero count means this region's occupancy can't be trusted.
func _capped(store: EditStore, top: float) -> int:
    var count := 0
    for k in n:
        for i in n:
            var xz := _column_xz(i, k)
            count += 1 if store.sample(Vector3(xz.x, top, xz.y)) < VoxelConstants.SDF_SOLID_THRESHOLD else 0
    return count


static func _mesh(store: EditStore, cell: Vector3i, camera: Vector3, dense: bool) -> Array:
    var root := Vector3i(((Vector3(cell) - Vector3.ONE * float(1 << (DEPTH - 1))) / ROOT_SNAP).floor() * ROOT_SNAP)
    var wmin := cell - Vector3i.ONE * WIN
    var wmax := cell + Vector3i.ONE * WIN
    var cam  := camera - Vector3(root)
    var m    := DCOctreeMesher.new()
    m.set_thread_count(mini(OS.get_processor_count(), 8))
    var arr: Array
    if dense:
        arr = m.mesh_world(store, root, DEPTH, 1.0, cam, 0.0, 0.0, false, MaterialPalette.colors(), wmin, wmax)
    else:
        arr = m.mesh_world(store, root, DEPTH, 1.0, cam, PROJ, EPS_LIVE, true, MaterialPalette.colors(), wmin, wmax)
    return [arr, Vector3(root)]


func _build(mesh_and_root: Array) -> void:
    var arr: Array = mesh_and_root[0]
    var root: Vector3 = mesh_and_root[1]
    tops.resize(n * n)
    for i in n * n:
        tops[i] = PackedFloat32Array()
    if arr.is_empty():
        inside.resize(n * n * n)
        return
    var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var c: PackedColorArray   = arr[Mesh.ARRAY_COLOR]
    var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
    for i in v.size():
        var p := v[i] + root
        if region.has_point(p):
            verts.append(p)
            colors.append(c[i])
        else:
            far.append(p)
    for t in range(0, idx.size(), 3):
        _raster(v[idx[t]] + root, v[idx[t + 1]] + root, v[idx[t + 2]] + root)
    for i in n * n:
        tops[i].sort()
    _fill_inside()


func _column_xz(i: int, k: int) -> Vector2:
    return Vector2(region.position.x + (float(i) + 0.5) * H + JITTER.x,
                   region.position.z + (float(k) + 0.5) * H + JITTER.y)


func _raster(a: Vector3, b: Vector3, c: Vector3) -> void:
    if maxf(a.y, maxf(b.y, c.y)) < region.position.y:
        return
    var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
    var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
    var i0 := maxi(0,     int(floor((lo.x - region.position.x) / H)) - 1)
    var i1 := mini(n - 1, int(floor((hi.x - region.position.x) / H)) + 1)
    var k0 := maxi(0,     int(floor((lo.y - region.position.z) / H)) - 1)
    var k1 := mini(n - 1, int(floor((hi.y - region.position.z) / H)) + 1)
    var e1 := Vector2(b.x - a.x, b.z - a.z)
    var e2 := Vector2(c.x - a.x, c.z - a.z)
    var det := e1.x * e2.y - e1.y * e2.x
    if absf(det) < 1e-12:
        return   # edge-on to +y: a vertical ray never crosses it
    for i in range(i0, i1 + 1):
        for k in range(k0, k1 + 1):
            var q := _column_xz(i, k) - Vector2(a.x, a.z)
            var u := (q.x * e2.y - q.y * e2.x) / det
            var w := (e1.x * q.y - e1.y * q.x) / det
            if u >= 0.0 and w >= 0.0 and u + w <= 1.0:
                tops[i + k * n].append(a.y + u * (b.y - a.y) + w * (c.y - a.y))


func _fill_inside() -> void:
    inside.resize(n * n * n)
    for k in n:
        for i in n:
            var col := tops[i + k * n]
            var above := col.size()
            var next := 0
            for j in n:
                var y := region.position.y + (float(j) + 0.5) * H
                while next < col.size() and col[next] <= y:
                    next += 1
                    above -= 1
                inside[i + j * n + k * n * n] = above & 1


func point(i: int, j: int, k: int) -> Vector3:
    var xz := _column_xz(i, k)
    return Vector3(xz.x, region.position.y + (float(j) + 0.5) * H, xz.y)


# Largest vertical move of a crossing that exists in both meshes (same count in the column), and
# how many columns changed crossing count (a topology change: a surface appeared or vanished).
func surface_shift(other: RefCounted) -> Vector2:
    var shift := 0.0
    var topo  := 0
    for c in n * n:
        var a := tops[c]
        var b: PackedFloat32Array = other.tops[c]
        if a.size() != b.size():
            topo += 1
            continue
        for t in a.size():
            if a[t] >= region.position.y - 1.0 and a[t] <= region.end.y + 1.0:
                shift = maxf(shift, absf(a[t] - b[t]))
    return Vector2(shift, topo)


# Vertices inside the region present in this mesh and not in `other` (moved or appeared).
func moved_vertices(other: RefCounted) -> PackedVector3Array:
    return _unmatched(verts, other.verts)


# How many window vertices outside the region moved or appeared: change the volume diff can't see.
func moved_far_vertices(other: RefCounted) -> int:
    return _unmatched(far, other.far).size()


static func _unmatched(mine: PackedVector3Array, theirs: PackedVector3Array) -> PackedVector3Array:
    var seen := {}
    for p in theirs:
        seen[Vector3i((p / SAME_VERT).round())] = true
    var moved := PackedVector3Array()
    for p in mine:
        if not seen.has(Vector3i((p / SAME_VERT).round())):
            moved.append(p)
    return moved


# Fraction of `cell` under the surface.
func solid_fraction(cell: Vector3i) -> float:
    var hit := 0
    var all := 0
    for k in n:
        for j in n:
            for i in n:
                if Vector3i(point(i, j, k).floor()) == cell:
                    all += 1
                    hit += inside[i + j * n + k * n * n]
    return float(hit) / float(maxi(all, 1))


# Volume this mesh gained / lost against `before`, where it sits relative to `target`, and which
# cells it touched: {added, removed, centroid, extent, by_cell: {cell: |dV|}}.
func volume_change(before: RefCounted) -> Dictionary:
    var dv      := H * H * H
    var added   := 0.0
    var removed := 0.0
    var sum     := Vector3.ZERO
    var extent  := AABB()
    var first   := true
    var by_cell := {}
    for k in n:
        for j in n:
            for i in n:
                var at := i + j * n + k * n * n
                if inside[at] == before.inside[at]:
                    continue
                var p := point(i, j, k)
                if inside[at] == 1:
                    added += dv
                else:
                    removed += dv
                sum += p
                extent = AABB(p, Vector3.ZERO) if first else extent.expand(p)
                first = false
                var cell := Vector3i(p.floor())
                by_cell[cell] = by_cell.get(cell, 0.0) + dv
    var count := (added + removed) / dv
    return {"added": added, "removed": removed, "extent": extent, "by_cell": by_cell,
        "centroid": sum / count if count > 0.0 else Vector3.INF}
