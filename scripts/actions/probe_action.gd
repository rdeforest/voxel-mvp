class_name ProbeAction
extends Action

# The "None" tool's click: print everything we know about the targeted cell to
# the LimboConsole — SDF/support state AND its place in the live PBD network
# (anchor/dynamic, awake/asleep, held-vs-falling, per-member load + fatigue).
# The targeted cell is highlighted in-world (preview) and can be nudged off the
# raycast hit with the Shift+W/A/E + wheel offset chord, same as build placement,
# so you can walk the probe through interior / floating cells.

var hit_pos:    Vector3
var hit_normal: Vector3
var offset:     Vector3
var terrain:    VoxelLodTerrain
var integrity:  StructuralIntegrity
var pbd:        PbdStructure


func _init(p_hit_pos: Vector3, p_hit_normal: Vector3, p_offset: Vector3, p_terrain: VoxelLodTerrain, p_integrity: StructuralIntegrity, p_pbd: PbdStructure) -> void:
    hit_pos    = p_hit_pos
    hit_normal = p_hit_normal
    offset     = p_offset
    terrain    = p_terrain
    integrity  = p_integrity
    pbd        = p_pbd


func validate() -> bool:
    return terrain != null


# Target the solid cell behind the hit surface (same convention as the voxel grid
# overlay), shifted by the placement offset.
func _target_cell() -> Vector3i:
    var p := hit_pos + offset - hit_normal * 0.01
    return Vector3i(floori(p.x), floori(p.y), floori(p.z))


func execute() -> void:
    var cell := _target_cell()

    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    var sdf       := vt.get_voxel_f(cell)
    var is_solid  := sdf < VoxelConstants.SDF_SOLID_THRESHOLD
    var tracked   := integrity.terrain_support.voxel_data.has(cell)
    var has_part  := integrity.has_part_cell(cell)

    LimboConsole.info("Cell %s" % cell)
    LimboConsole.info("  SDF      %.3f (%s)" % [sdf, "solid" if is_solid else "air"])
    LimboConsole.info("  tracked  %s" % tracked)
    if tracked:
        var rec: VoxelRecord = integrity.terrain_support.voxel_data[cell]
        LimboConsole.info("  support  %.3f"  % rec.support)
        LimboConsole.info("  dirty    %s"    % rec.dirty)
        LimboConsole.info("  material %s"    % rec.material.name)
    LimboConsole.info("  part     %s" % has_part)
    _log_pbd(cell)


func _log_pbd(cell: Vector3i) -> void:
    if pbd == null:
        LimboConsole.info("  PBD      (no structure)")
        return
    var p := pbd.probe(cell)
    if not p.get("enabled", false):
        LimboConsole.info("  PBD      off (enable with `physics_active on`)")
        return
    if not p.get("in_network", false):
        LimboConsole.info("  PBD      cell not in network")
        return
    LimboConsole.info("  PBD node %d  %s  %s  %s" % [
        p.node,
        "ANCHOR" if p.pinned else "dynamic",
        "asleep" if p.sleeping else "awake",
        "held (anchored)" if p.anchored else "FALLING (detached)",
    ])
    LimboConsole.info("    peak load %.0f%% of limit, peak damage %.2f, %d live members" % [
        p.peak_ratio * 100.0, p.peak_damage, p.members.size(),
    ])


func preview() -> ActionPreview:
    var p := ActionPreview.new()
    p.solid.append(_target_cell())   # highlight the targeted cell
    return p
