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
# `work` is the actions' shared shape: an Array of entries whose [0] is the Vector3i cell and
# [1] is the new SDF. `material_of(entry) -> int` returns the material id for an edited cell,
# or < 0 to keep the cell's current material (carved/air cells, or ops that don't repaint).
# Returns the world-space AABB written (for the terrain_sdf_changed event).
static func cells(store: EditStore, work: Array, material_of: Callable) -> AABB:
    if work.is_empty():
        return AABB()
    var lo_cell: Vector3i = work[0][0]
    var hi_cell: Vector3i = work[0][0]
    for entry in work:
        var cell: Vector3i = entry[0]
        lo_cell = Vector3i(mini(lo_cell.x, cell.x), mini(lo_cell.y, cell.y), mini(lo_cell.z, cell.z))
        hi_cell = Vector3i(maxi(hi_cell.x, cell.x), maxi(hi_cell.y, cell.y), maxi(hi_cell.z, cell.z))
    lo_cell -= Vector3i.ONE
    hi_cell += Vector3i.ONE
    var span := hi_cell - lo_cell
    var dim  := maxi(span.x, maxi(span.y, span.z)) + 1
    var sdf := PackedFloat32Array()
    var indices := PackedByteArray()
    sdf.resize(dim * dim * dim)
    indices.resize(dim * dim * dim)
    for z in dim:
        for y in dim:
            for x in dim:
                var point := lo_cell + Vector3i(x, y, z)
                var index := x + dim * (y + dim * z)
                sdf[index] = store.sample(Vector3(point))
                indices[index] = store.material_at(Vector3(point))
    for entry in work:
        var cell: Vector3i = entry[0]
        var local := cell - lo_cell
        var index := local.x + dim * (local.y + dim * local.z)
        sdf[index] = entry[1]
        var material: int = material_of.call(entry)
        if material >= 0:
            indices[index] = material
    store.write_region(sdf, indices, dim, Vector3(lo_cell), 1.0)
    return AABB(Vector3(lo_cell), Vector3(span))
