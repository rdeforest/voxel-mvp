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


func validate() -> bool:
    return store != null


# How many of the cell's 8 corners are inside solid — the DC mesher's own solidity test. A cell
# with triangles but 0 solid corners is a stale-mesh artifact; 1..7 is a normal surface cell.
func _corner_solid_count(cell: Vector3i) -> int:
    var n := 0
    for dx in [0, 1]:
        for dy in [0, 1]:
            for dz in [0, 1]:
                if store.sample(Vector3(cell + Vector3i(dx, dy, dz))) < VoxelConstants.SDF_SOLID_THRESHOLD:
                    n += 1
    return n


# Target the solid cell behind the hit surface (same convention as the voxel grid
# overlay), shifted by the placement offset.
func _target_cell() -> Vector3i:
    var p := hit_pos + offset - hit_normal * VoxelConstants.SURFACE_NUDGE
    return Vector3i(floori(p.x), floori(p.y), floori(p.z))


func execute() -> void:
    for line in report():
        LimboConsole.info(line)


# The targeted cell's full read-out, as lines. Shared by the click (console log) and the live
# probe HUD, so both always agree. Store SDF + material are shown for ANY cell (solid terrain that
# isn't tracked still reports its material), which is what makes scanning a scene useful.
func report() -> PackedStringArray:
    var cell := _target_cell()
    var out := PackedStringArray()

    var center   := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
    var sdf      := store.sample(center)   # center: matches the thaw/collision solidity convention
    var is_solid := sdf < VoxelConstants.SDF_SOLID_THRESHOLD
    var mat_idx  := store.material_at(center)
    var corners  := _corner_solid_count(cell)
    var tracked  := integrity.terrain_support.voxel_data.has(cell)

    out.append("Cell %s" % cell)
    out.append("  SDF      %.3f (%s)" % [sdf, "solid" if is_solid else "air"])
    # 0/8 with visible triangles = a stale-mesh artifact (mesh out of sync with the field);
    # 1..7/8 = an ordinary surface cell (the zero-crossing legitimately passes through it).
    out.append("  corners  %d/8 solid" % corners)
    out.append("  material %d (%s)" % [mat_idx, MaterialPalette.name_of(mat_idx)])
    out.append("  tracked  %s" % tracked)
    if tracked:
        var rec: VoxelRecord = integrity.terrain_support.voxel_data[cell]
        out.append("  support  %.3f" % rec.support)
        out.append("  dirty    %s" % rec.dirty)
    return out


func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.solid.append(_target_cell())   # highlight the targeted cell
    return p
