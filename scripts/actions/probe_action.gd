class_name ProbeAction
extends Action

# The "None" tool's click: print everything we know about the targeted
# cell to the LimboConsole. Useful for debugging the phantom-strain
# class of bugs and generally for understanding what the structural
# system thinks of a given cell.

var hit_pos:    Vector3
var hit_normal: Vector3
var terrain:    VoxelLodTerrain
var integrity:  StructuralIntegrity


func _init(p_hit_pos: Vector3, p_hit_normal: Vector3, p_terrain: VoxelLodTerrain, p_integrity: StructuralIntegrity) -> void:
    hit_pos    = p_hit_pos
    hit_normal = p_hit_normal
    terrain    = p_terrain
    integrity  = p_integrity


func validate() -> bool:
    return terrain != null

func execute() -> void:
    # Target the solid cell behind the hit surface (same convention as
    # the voxel grid overlay).
    var probe_pos := hit_pos - hit_normal * 0.01
    var cell      := Vector3i(floori(probe_pos.x), floori(probe_pos.y), floori(probe_pos.z))

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

func preview() -> ActionPreview:
    return ActionPreview.new()   # no visual preview for probe
