class_name ProbeAction
extends Action

# The "None" tool's click: print everything we know about the targeted cell to
# the LimboConsole — SDF/material/support and its tracked-set membership.
# The targeted cell is highlighted in-world (preview) and can be nudged off the
# raycast hit with the Shift+W/A/E + wheel offset chord, same as build placement,
# so you can walk the probe through interior / floating cells.

var hit_pos:    Vector3
var hit_normal: Vector3
var offset:     Vector3
var store:      EditStore
var integrity:  StructuralIntegrity


func _init(p_hit_pos: Vector3, p_hit_normal: Vector3, p_offset: Vector3, p_ctx: ActionContext) -> void:
    hit_pos    = p_hit_pos
    hit_normal = p_hit_normal
    offset     = p_offset
    store      = p_ctx.store
    integrity  = p_ctx.integrity


func to_step() -> Dictionary:
    return {
        "hit_pos":    StepFields.encode_vec3(hit_pos),
        "hit_normal": StepFields.encode_vec3(hit_normal),
        "offset":     StepFields.encode_vec3(offset),
    }

static func from_step(f: StepFields, ctx: ActionContext) -> Action:
    return ProbeAction.new(f.vec3("hit_pos"), f.vec3("hit_normal"), f.vec3("offset"), ctx)


func validate() -> bool:
    return store != null


# The cell's 8 lattice corners as the DC mesher samples them (store.sample, the upper side of every
# leaf boundary), corner k at cell + CubeGeometry.corner(k), x fastest. These are the 1 m corners:
# the mesher reads exactly them where the render reaches its 1 m floor; a coarser render leaf
# samples its own, wider corners.
func _corner_values(cell: Vector3i) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    for k in 8:
        out.append(store.sample(Vector3(cell) + CubeGeometry.corner(k)))
    return out


# The mesher's sign test (dc_octree.h, (fa < 0) != (fb < 0), a literal 0 that SDF_SOLID_THRESHOLD
# mirrors): an edge carries a surface crossing where its two corners lie on opposite sides of it.
# How many of the 12 cell edges do.
static func _crossing_edges(values: PackedFloat64Array) -> int:
    var n := 0
    for edge: Array in CubeGeometry.EDGES:
        if _is_solid(values[edge[0]]) != _is_solid(values[edge[1]]):
            n += 1
    return n

static func _is_solid(v: float) -> bool:
    return v < VoxelConstants.SDF_SOLID_THRESHOLD


# Target the solid cell behind the hit surface (same convention as the voxel grid
# overlay), shifted by the placement offset.
func target_cell() -> Vector3i:
    var p := hit_pos + offset - hit_normal * VoxelConstants.SURFACE_NUDGE
    return Vector3i(floori(p.x), floori(p.y), floori(p.z))


func execute() -> void:
    for line in report():
        LimboConsole.info(line)


# The targeted cell's full read-out, as lines. Shared by the click (console log) and the live
# probe HUD, so both always agree. Store SDF + material are shown for ANY cell (solid terrain that
# isn't tracked still reports its material), which is what makes scanning a scene useful.
func report() -> PackedStringArray:
    var cell := target_cell()
    var out := PackedStringArray()

    var sdf      := TerrainProbe.sdf(store, cell)   # at the cell's sample point, like every solidity read
    var mat_idx  := TerrainProbe.material(store, cell)
    var tracked  := integrity.terrain_support.voxel_data.has(cell)

    out.append("Cell %s" % cell)
    out.append("  SDF      %.3f (%s)" % [sdf, "solid" if _is_solid(sdf) else "air"])
    out.append("  material %d (%s)" % [mat_idx, MaterialPalette.name_of(mat_idx)])
    out.append("  leaf     %s" % ("edited (the store holds it)" if store.has_edit(VoxelUtils.sample_point(cell))
        else "unedited (the generator's)"))
    out.append_array(_corner_lines(cell))
    out.append("  tracked  %s" % tracked)
    if tracked:
        var rec: VoxelRecord = integrity.terrain_support.voxel_data[cell]
        out.append("  support  %.3f" % rec.support)
        out.append("  dirty    %s" % rec.dirty)
    return out


# The corners the mesher reads, its sign test on them, and every corner where the cell's own leaf
# holds a different value (a seam between leaves that disagree, which the mesher doesn't see).
# A sign change on no edge with triangles on screen is a stale mesh; on some edge, a surface cell.
func _corner_lines(cell: Vector3i) -> PackedStringArray:
    var values := _corner_values(cell)
    var solid  := 0
    for v in values:
        solid += 1 if _is_solid(v) else 0

    var crossing := _crossing_edges(values)
    var out := PackedStringArray()
    out.append("  corners  z=0 %s" % _row(values, 0))
    out.append("           z=1 %s" % _row(values, 4))
    out.append("  sign     %d/8 solid, %d/12 edges cross: %s" % [solid, crossing,
        "the mesher puts a surface here" if crossing > 0 else "no surface for the mesher"])

    var centre := VoxelUtils.sample_point(cell)
    for k in 8:
        var own := store.sample_toward(Vector3(cell) + CubeGeometry.corner(k), centre)
        if own != values[k]:
            out.append("  seam     corner %d: this cell's leaf holds %.4f" % [k, own])
    return out


# Corners k .. k + 3 (y, then x), as "(x0 y0) (x1 y0) (x0 y1) (x1 y1)".
static func _row(values: PackedFloat64Array, first: int) -> String:
    var cells := PackedStringArray()
    for k in range(first, first + 4):
        cells.append("%8.4f" % values[k])
    return " ".join(cells)


func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.solid.append(target_cell())   # highlight the targeted cell
    return p
