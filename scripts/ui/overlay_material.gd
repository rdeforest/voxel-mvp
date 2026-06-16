class_name OverlayMaterial

# Shared factory for the debug overlay StandardMaterial3D. All three overlays
# (voxel_preview_renderer, invalidation_overlay, voxel_grid_overlay) need the same
# unshaded / vertex-colour / alpha-transparent / cull-off setup; the only difference
# is whether no_depth_test is on (see-through) or off (depth-tested).

static func make(no_depth_test: bool) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.vertex_color_use_as_albedo = true
    mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
    mat.no_depth_test              = no_depth_test
    mat.render_priority            = VoxelConstants.OVERLAY_RENDER_PRIORITY
    return mat
